"""
Abordagem B: heurística manual com BeautifulSoup/lxml.

Regra:
1. Remove <script>, <style>, <nav>, <footer>, <aside>, <form>, <header> e
   qualquer elemento cujo class/id bata no DENYLIST (menu, ads, comentários,
   relacionados, newsletter, etc).
2. Se existir <article>, usa o texto de todos os <p> dentro dele.
3. Senão, entre todos os containers (div/section/main), escolhe o que tem
   maior soma de texto em <p> diretamente ou descendentes, e usa os <p>
   desse container.
4. Concatena os parágrafos com quebra de linha, remove espaços redundantes.
"""
import re
from bs4 import BeautifulSoup, Comment

DENYLIST = re.compile(
    r"(related|relacionad|comment|coment|sidebar|side-bar|\bnav\b|navbar|"
    r"footer|rodape|\bads?\b|advert|publicidade|banner|leia-tambem|"
    r"leia_tambem|leiatambem|newsletter|subscribe|assinatura|assine|"
    r"social|compartilh|share|breadcrumb|menu|cookie|tags?-list|"
    r"widget|promo|recommend|recirc|mais-lidas|mais-noticias|outbrain|"
    r"taboola)",
    re.I,
)
# NOTA (achado do spike): "paywall" foi removido do denylist de propósito.
# No HTML real do Estadão, o container que envolve os parágrafos GRATUITOS
# (o preview antes do corte) se chama literalmente `-paywall-parent`
# (é o "pai da barreira de paywall", não o conteúdo pago). Um denylist
# ingênuo por substring apagava o próprio texto do artigo por causa disso.
# Detecção de paywall de verdade é feita à parte, em PAYWALL_HINTS
# (compare.py), sobre o texto já extraído — não sobre nomes de classe CSS.

STRUCTURAL_REMOVE = ["script", "style", "nav", "footer", "aside", "form", "header", "noscript"]


def _clean(soup: BeautifulSoup) -> BeautifulSoup:
    for comment in soup.find_all(string=lambda s: isinstance(s, Comment)):
        comment.extract()
    for tag_name in STRUCTURAL_REMOVE:
        for tag in soup.find_all(tag_name):
            tag.decompose()
    # materializa a lista antes de remover: decompose() de um ancestro
    # invalida os descendentes que ainda estariam na lista de find_all.
    # NUNCA aplica o denylist em tags estruturais de topo (html/body/main/
    # article): sites modernos empilham dezenas de classes utilitárias de
    # tema/estado nessas tags (ex.: g1.globo.com tem
    # `glb-theme-elem-sharebar--touch` na própria <html>), e uma substring
    # como "share" bateria nelas, apagando a página inteira — achado real
    # deste spike, não um cenário hipotético.
    STRUCTURAL_SKIP = {"html", "body", "main", "article"}
    for tag in list(soup.find_all(True)):
        if tag.name in STRUCTURAL_SKIP:
            continue
        if tag.parent is None or tag.attrs is None:
            continue  # já removido junto com algum ancestro
        cls = " ".join(tag.get("class", []) or [])
        _id = tag.get("id", "") or ""
        if DENYLIST.search(cls) or DENYLIST.search(_id):
            tag.decompose()
    return soup


def _paragraph_text(container) -> str:
    paras = container.find_all("p")
    texts = [p.get_text(" ", strip=True) for p in paras]
    texts = [t for t in texts if t]
    return "\n\n".join(texts)


def extract(html: str, url: str = None) -> str | None:
    soup = BeautifulSoup(html, "lxml")
    soup = _clean(soup)

    article = soup.find("article")
    if article is not None:
        text = _paragraph_text(article)
        if len(text) >= 200:
            return text

    # sem <article> útil: entre os containers (div/section/main), o texto de
    # <p> tende a "empilhar" em containers ancestrais (um <div> pai sempre
    # contém o texto de todos os filhos). Para não degenerar sempre para
    # <body>, mede o texto de <p> de cada container e escolhe o MENOR
    # container (mais profundo) que ainda cobre >=90% do maior total
    # encontrado — ou seja, o container mais "apertado" ao redor do texto.
    candidates = []
    for container in soup.find_all(["div", "section", "main", "body"]):
        text = _paragraph_text(container)
        if len(text) >= 200:
            candidates.append((len(text), container, text))

    if not candidates:
        return None

    max_len = max(c[0] for c in candidates)
    threshold = max_len * 0.9
    tight_candidates = [c for c in candidates if c[0] >= threshold]
    # entre os que cobrem o essencial do texto, pega o de menor tamanho de
    # subárvore (menos elementos = mais "apertado", menos provável de ser
    # um wrapper genérico tipo <body>)
    tight_candidates.sort(key=lambda c: len(c[1].find_all(True)))
    return tight_candidates[0][2]
