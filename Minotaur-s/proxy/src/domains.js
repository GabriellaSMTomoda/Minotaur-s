export const ALLOWED_DOMAINS = [
  "g1.globo.com",
  "oglobo.globo.com",
  "folha.uol.com.br",
  "estadao.com.br",
  "cnnbrasil.com.br",
  "veja.abril.com.br",
  "valor.globo.com",
  "exame.com",
  "r7.com",
  "terra.com.br",
  "metropoles.com",
  "poder360.com.br",
  "gauchazh.clicrbs.com.br",
  "correiobraziliense.com.br",
  "agenciabrasil.ebc.com.br",
  "otempo.com.br",
  "www.band.com.br",
  "ge.globo.com",
  "aosfatos.org",
  "www.agencialupa.org",
  "bbc.com",
  "dw.com",
  "elpais.com",
  "apnews.com",
  "gov.br",
  "agenciagov.ebc.com.br",
  "camara.leg.br",
  "senado.leg.br",
  "stf.jus.br",
  "tse.jus.br",
  "who.int"
];
// Encyclopedic source served only by POST /wiki. Kept out of ALLOWED_DOMAINS on purpose:
// that list is sent to Tavily and mirrors the Swift allowlist; the app adds this host in its own stage.
export const WIKIPEDIA_HOST = "pt.wikipedia.org";
export const FACT_CHECK_DOMAINS =["aosfatos.org", "www.agencialupa.org", "g1.globo.com", "estadao.com.br"];
