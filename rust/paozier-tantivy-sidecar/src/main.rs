use std::fs;
use std::io::{self, Read};
use std::path::Path;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use tantivy::collector::TopDocs;
use tantivy::query::QueryParser;
use tantivy::schema::{
    IndexRecordOption, Schema, TextFieldIndexing, TextOptions, Value, STORED, STRING,
};
use tantivy::tokenizer::NgramTokenizer;
use tantivy::TantivyDocument;
use tantivy::{doc, Index, ReloadPolicy, Term};

fn main() {
    if let Err(error) = run() {
        eprintln!("{error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let command = std::env::args()
        .nth(1)
        .context("missing tantivy command")?;
    match command.as_str() {
        "apply" => apply_batch(),
        "search" => search_index(),
        other => anyhow::bail!("unsupported tantivy command: {other}"),
    }
}

fn apply_batch() -> Result<()> {
    let payload: ApplyPayload = read_stdin_json()?;
    let handle = open_or_create_index(&payload.index_path)?;
    let mut writer = handle.index.writer(100_000_000)?;

    for operation in payload.operations {
        match operation {
            Operation::Add { path, content } => {
                let title = Path::new(&path)
                    .file_name()
                    .map(|name| name.to_string_lossy().to_string())
                    .unwrap_or_default();
                writer.delete_term(Term::from_field_text(handle.fields.path, &path));
                writer.add_document(doc!(
                    handle.fields.path => path,
                    handle.fields.title => title,
                    handle.fields.content => content.clone(),
                    handle.fields.content_ngram => content
                ))?;
            }
            Operation::Delete { path } => {
                writer.delete_term(Term::from_field_text(handle.fields.path, &path));
            }
        }
    }

    writer.commit()?;
    writer.wait_merging_threads()?;
    write_stdout_json(&OkResponse { ok: true })
}

fn search_index() -> Result<()> {
    let payload: SearchPayload = read_stdin_json()?;
    let index_path = Path::new(&payload.index_path);
    if !index_path.join("meta.json").exists() {
        return write_stdout_json(&SearchResponse { hits: Vec::new() });
    }

    let handle = open_or_create_index(&payload.index_path)?;
    let reader = handle
        .index
        .reader_builder()
        .reload_policy(ReloadPolicy::Manual)
        .try_into()?;
    reader.reload()?;
    let searcher = reader.searcher();

    let mut parser = QueryParser::for_index(
        &handle.index,
        vec![handle.fields.content, handle.fields.content_ngram, handle.fields.title],
    );
    parser.set_conjunction_by_default();
    parser.set_field_boost(handle.fields.content, 1.0);
    parser.set_field_boost(handle.fields.content_ngram, 0.45);
    parser.set_field_boost(handle.fields.title, 0.15);

    let (query, _errors) = parser.parse_query_lenient(&payload.query);
    let top_docs = searcher.search(&query, &TopDocs::with_limit(payload.limit).order_by_score())?;

    let mut hits = Vec::with_capacity(top_docs.len());
    for (score, address) in top_docs {
        let document = searcher.doc::<TantivyDocument>(address)?;
        let Some(path_value) = document.get_first(handle.fields.path) else {
            continue;
        };
        let Some(path) = path_value.as_str() else {
            continue;
        };
        hits.push(SearchHit {
            path: path.to_string(),
            score: score as f64,
        });
    }

    write_stdout_json(&SearchResponse { hits })
}

fn open_or_create_index(index_path: &str) -> Result<IndexHandle> {
    let index_dir = Path::new(index_path);
    fs::create_dir_all(index_dir)?;

    let schema = build_schema();
    let index = if index_dir.join("meta.json").exists() {
        Index::open_in_dir(index_dir)?
    } else {
        Index::create_in_dir(index_dir, schema.clone())?
    };

    register_tokenizers(&index)?;
    let schema = index.schema();

    Ok(IndexHandle {
        fields: IndexFields {
            path: schema.get_field("path")?,
            title: schema.get_field("title")?,
            content: schema.get_field("content")?,
            content_ngram: schema.get_field("content_ngram")?,
        },
        index,
    })
}

fn build_schema() -> Schema {
    let mut schema_builder = Schema::builder();
    schema_builder.add_text_field("path", STRING | STORED);

    let title_options = TextOptions::default()
        .set_indexing_options(
            TextFieldIndexing::default()
                .set_tokenizer("default")
                .set_index_option(IndexRecordOption::WithFreqsAndPositions),
        )
        .set_stored();
    schema_builder.add_text_field("title", title_options);

    let content_options = TextOptions::default().set_indexing_options(
        TextFieldIndexing::default()
            .set_tokenizer("default")
            .set_index_option(IndexRecordOption::WithFreqsAndPositions),
    );
    schema_builder.add_text_field("content", content_options.clone());

    let content_ngram_options = TextOptions::default().set_indexing_options(
        TextFieldIndexing::default()
            .set_tokenizer("paozier_ngram")
            .set_index_option(IndexRecordOption::WithFreqsAndPositions),
    );
    schema_builder.add_text_field("content_ngram", content_ngram_options);
    schema_builder.build()
}

fn register_tokenizers(index: &Index) -> Result<()> {
    index
        .tokenizers()
        .register("paozier_ngram", NgramTokenizer::new(2, 3, false)?);
    Ok(())
}

fn read_stdin_json<T: for<'de> Deserialize<'de>>() -> Result<T> {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input)?;
    serde_json::from_str(&input).context("invalid tantivy sidecar payload")
}

fn write_stdout_json<T: Serialize>(value: &T) -> Result<()> {
    let stdout = io::stdout();
    serde_json::to_writer(stdout.lock(), value)?;
    Ok(())
}

#[derive(Deserialize)]
struct ApplyPayload {
    index_path: String,
    operations: Vec<Operation>,
}

#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "lowercase")]
enum Operation {
    Add { path: String, content: String },
    Delete { path: String },
}

#[derive(Deserialize)]
struct SearchPayload {
    index_path: String,
    query: String,
    limit: usize,
}

#[derive(Serialize)]
struct OkResponse {
    ok: bool,
}

#[derive(Serialize)]
struct SearchResponse {
    hits: Vec<SearchHit>,
}

#[derive(Serialize)]
struct SearchHit {
    path: String,
    score: f64,
}

struct IndexHandle {
    fields: IndexFields,
    index: Index,
}

struct IndexFields {
    path: tantivy::schema::Field,
    title: tantivy::schema::Field,
    content: tantivy::schema::Field,
    content_ngram: tantivy::schema::Field,
}
