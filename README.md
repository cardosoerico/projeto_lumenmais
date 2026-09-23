# LumenMais — Análise de Assinatura SaaS

Análise em SQL de dados de assinatura de um SaaS fictício de streaming (LumenMais): MRR, churn, conversão trial→pago e segmentação por canal de aquisição e dispositivo, respondendo perguntas de negócio reais de três stakeholders (CFO, Growth, Product).

## Estrutura do projeto

```
projeto_lumenmais/
├── data/                        # Dados brutos (CSV)
│   ├── users.csv
│   ├── usage_events.csv
│   └── subscription_events.csv
├── docs/
│   └── perguntas_stakeholders.md  # Perguntas de negócio, organizadas por complexidade analítica
├── sql/
│   ├── 01_schema.sql             # Criação das tabelas
│   ├── 02_analises.sql           # Consultas de MRR, conversão trial→pago e engajamento
│   └── 03_views.sql              # Views prontas para consumo por dashboard/BI
└── README.md
```

## Dados

- **users.csv** — cadastro dos usuários: data de inscrição, canal de aquisição, país, dispositivo principal e se passou por trial.
- **usage_events.csv** — sessões de uso: data, dispositivo, gênero assistido, minutos assistidos e se completou o conteúdo.
- **subscription_events.csv** — histórico de eventos de assinatura: início de trial, início/cancelamento de assinatura, upgrade/downgrade, com o plano e o impacto em MRR de cada evento.

## O que as consultas respondem

As perguntas completas, com métrica, técnica e armadilha de análise para cada uma, estão em [`docs/perguntas_stakeholders.md`](docs/perguntas_stakeholders.md). Em resumo:

- **MRR ativo e por plano** — reconstrução do estado vigente de cada assinante via window function, para não contar cancelamentos e reativações como receita adicional.
- **Conversão trial → pago** — geral e por canal de aquisição.
- **Engajamento pré-cancelamento** — comparação de minutos assistidos e taxa de conclusão entre quem cancelou e quem permanece ativo, nos 30 dias antes do evento.

`sql/03_views.sql` consolida essas reconstruções em três views (`vw_usage_summary`, `vw_subscriber_current_state`, `vw_dashboard_master`) prontas para alimentar um dashboard.

## Como rodar

1. Crie as tabelas com `sql/01_schema.sql` (PostgreSQL).
2. Importe os CSVs de `data/` nas tabelas correspondentes.
3. Rode as consultas de `sql/02_analises.sql` ou crie as views de `sql/03_views.sql`.
