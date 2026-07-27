"""Abordagem A: trafilatura (biblioteca de readability pronta)."""
import trafilatura


def extract(html: str, url: str = None) -> str | None:
    text = trafilatura.extract(
        html,
        url=url,
        include_comments=False,
        include_tables=False,
        favor_precision=True,
    )
    return text
