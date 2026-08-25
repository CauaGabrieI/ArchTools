# Pós-auditoria — verificação das correções

Data: 2026-08-25.

## Correções verificadas

| Achado anterior | Resultado |
| --- | --- |
| GPU Virtio/desconhecida detectada como AMD | Corrigido: a detecção exige identificadores de fornecedor delimitados; Virtio e unknown não planejam drivers específicos. |
| `pacman -Rns` e falhas ocultas | Corrigido: remoção conservadora usa `pacman -R --` apenas para itens registrados; falhas são retornadas. |
| Backup por basename | Corrigido: manifest registra caminho original absoluto, caminho absoluto da cópia, hash, data, módulo e operação. |
| Arquivo criado pelo projeto | Corrigido: manifest registra `created`; rollback remove somente entradas com essa operação. |
| Dry-run persistente | Corrigido: log e estado persistentes não são inicializados em dry-run. |
| Backup duplicado | Corrigido: caminho + hash identificam backup já existente. |
| `lsblk` ausente | Corrigido: detecção entra em modo `limited` e continua. |
| `bluetoothctl` sem hardware | Corrigido: software e hardware são registrados separadamente; somente evidência física marca Bluetooth detectado. |
| Distribuição | Corrigido: `/etc/os-release` deve indicar `ID=arch` ou `ID_LIKE` contendo `arch`. |
| Estado de serviço no rollback | Corrigido para `enabled`, `disabled` e `masked`; estados sem restauração segura são explicitamente ignorados com aviso. |

## Execução de verificação

`bash -n` passou em todos os scripts. Os testes de CPU, GPU, armazenamento, rede, pacotes, dry-run e backup passaram. A matriz de GPU cobre AMD, Intel, NVIDIA, combinações híbridas, Virtio, desconhecida e ausência de GPU; ela também confirma a ausência de pacotes específicos no plano para Virtio/desconhecida.

`shellcheck` não está disponível no ambiente, portanto não há resultado dessa ferramenta. A verificação também não ocorreu em uma instalação Arch isolada: antes de uso real, execute a suíte e um dry-run em Arch Linux com os repositórios e systemd reais.
