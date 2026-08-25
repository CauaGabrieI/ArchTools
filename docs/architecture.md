# Arquitetura

Fluxo obrigatório: detectar → analisar → decidir → mostrar plano → confirmar → executar → validar → relatório. `install.sh` só carrega `lib/core.sh`. Detectores preenchem o array associativo `HARDWARE`; planejadores apenas adicionam itens ao array `PLAN_*`; executor é o único ponto que chama pacman ou systemctl.

Os módulos usam alternativas e retornam valores vazios quando uma ferramenta opcional não existe. Isso permite executar detecção parcial sem falha.
