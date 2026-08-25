# Arquitetura

Fluxo obrigatório: detectar → analisar → decidir → mostrar plano → confirmar → executar → validar → relatório. `install.sh` e o CLI `archtools` carregam o mesmo core; ferramentas em `tools/` são wrappers finos da API em `lib/api.sh`. Detectores preenchem o array associativo `HARDWARE`; planejadores apenas adicionam itens ao array `PLAN_*`; executor é o único ponto que chama pacman ou systemctl.

O CLI unificado expõe comandos independentes sem obrigar o pós-instalador completo:

```text
archtools hardware detect
archtools diagnostics run
archtools drivers detect
archtools drivers install --dry-run
archtools profile desktop --dry-run
```

`install.sh` continua compatível como orquestrador legado. Perfis reutilizam os
mesmos planejadores de pacotes, serviços e drivers, e não executam scripts em
`tools/`.

Os módulos usam alternativas e retornam valores vazios quando uma ferramenta opcional não existe. Isso permite executar detecção parcial sem falha.
