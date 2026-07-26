/**
 * Proxy da API de busca Tavily (DT-21 / NF-09).
 *
 * O app iOS não pode embarcar a chave da Tavily: chave em binário é extraível por
 * engenharia reversa, então o proxy é a única proteção real. Este Worker recebe a
 * requisição do app, injeta a chave a partir de um secret e repassa a resposta.
 *
 * É stateless por decisão: não lê, não grava e não registra o texto do usuário em lugar
 * nenhum (NF-07 / DT-13). A query passa pela memória do Worker e vai embora com a resposta.
 */

const TAVILY_ENDPOINT = "https://api.tavily.com/search";

/** Campos que o app pode enviar. Qualquer outro é descartado. */
const ALLOWED_FIELDS = ["query", "search_depth", "max_results", "include_domains"];

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return json(405, { detail: { error: "Method not allowed. Use POST." } });
    }

    if (!env.TAVILY_API_KEY) {
      // Secret não configurado no deploy. Erro de configuração, não de uso — o app trata
      // como falha de busca não-retriável.
      return json(500, { detail: { error: "Proxy misconfigured: TAVILY_API_KEY is not set." } });
    }

    let incoming;
    try {
      incoming = await request.json();
    } catch {
      return json(400, { detail: { error: "Malformed JSON body." } });
    }

    if (typeof incoming.query !== "string" || incoming.query.trim() === "") {
      return json(400, { detail: { error: "Field 'query' is required." } });
    }

    // Repassa só o que o app tem permissão de controlar. Copiar o corpo inteiro deixaria o
    // cliente injetar parâmetros de custo (search_depth caro) ou sobrescrever a api_key.
    const body = { api_key: env.TAVILY_API_KEY };
    for (const field of ALLOWED_FIELDS) {
      if (incoming[field] !== undefined) body[field] = incoming[field];
    }

    let upstream;
    try {
      upstream = await fetch(TAVILY_ENDPOINT, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${env.TAVILY_API_KEY}`,
        },
        body: JSON.stringify(body),
      });
    } catch (error) {
      // Falha de rede entre o Worker e a Tavily. 502 é 5xx, então o app faz a tentativa
      // extra da RF-04.6 — que é o comportamento desejado para erro transitório.
      return json(502, { detail: { error: "Upstream request failed." } });
    }

    // Status e corpo passam intactos: o app depende de 401/429/5xx para decidir retry e
    // categoria de erro (RF-10.4 / DT-27). Reescrever o status aqui quebraria essa decisão.
    return new Response(upstream.body, {
      status: upstream.status,
      headers: { "Content-Type": "application/json" },
    });
  },
};
