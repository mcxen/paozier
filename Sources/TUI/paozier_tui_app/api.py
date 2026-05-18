import httpx

from .constants import BASE_URL


class PaozierAPI:
    def __init__(self, base_url: str = BASE_URL, timeout: float = 5.0) -> None:
        self._client = httpx.AsyncClient(base_url=base_url, timeout=timeout)

    async def search(self, query: str) -> dict:
        response = await self._client.get("/api/search", params={"q": query})
        return response.json()

    async def status(self) -> dict:
        response = await self._client.get("/api/status")
        return response.json()

    async def content(self, path: str) -> httpx.Response:
        return await self._client.get("/api/content", params={"path": path})

    async def open_file(self, path: str) -> None:
        await self._client.get("/api/open", params={"path": path})

    async def reveal_file(self, path: str) -> None:
        await self._client.get("/api/reveal", params={"path": path})
