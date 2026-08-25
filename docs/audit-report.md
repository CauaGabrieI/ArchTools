# ARCH SMART POST-INSTALL — AUDIT REPORT

Data da auditoria: 2026-08-25. Escopo: código atual, testes locais e simulações com `pacman` simulado. O ambiente de auditoria não é Arch Linux e não foi usado para executar `pacman`, `sudo` ou alterações reais de serviços.

| Área | Resultado | Observação |
| --- | --- | --- |
| Architecture | PASS | Detectar, planejar, confirmar, executar e validar estão separados. Detectores não chamam `pacman`; planejamento não chama `sudo` nem modifica serviços. |
| Security | FAIL | A detecção incorreta de GPU pode planejar drivers AMD para hardware desconhecido/virtual. Remoção com `pacman -Rns` pode remover dependências órfãs fora do registro do projeto. |
| Hardware detection | FAIL | Falso positivo AMD confirmado para GPU Virtio e GPU desconhecida; armazenamento não tolera a ausência de `lsblk`. |
| Package management | FAIL | Falhas de remoção são ocultadas e `-Rns` é agressivo para uninstall/rollback. |
| Idempotency | FAIL | Pacotes e serviços do plano não duplicam, mas `backup_file` recria backups para o mesmo arquivo sem verificação. |
| Dry-run | FAIL | Cria diretório/arquivos de estado persistente e log antes de verificar `DRY_RUN`. |
| Backup | FAIL | Não evita duplicatas e rollback escolhe backup por basename, que não é um identificador único. |
| Rollback | FAIL | Pode restaurar o arquivo errado em colisão de basename, não remove arquivos que não existiam antes e pode ocultar falhas. |
| Uninstall | FAIL | Pode remover dependências não registradas; falhas são ocultadas; não restaura estado de serviços. |
| Error handling | FAIL | O trap cobre falhas críticas de instalação/habilitação, mas falhas de remoção e `systemctl disable` são explicitamente suprimidas. |
| ShellCheck | FAIL (não executado) | `shellcheck` não está instalado no ambiente de auditoria. Não foi possível emitir diagnóstico da ferramenta. |
| Tests | PASS, cobertura insuficiente | Os seis testes existentes passaram; eles não cobrem rollback, backup, falha de pacman/systemctl ou todas as GPUs. |

## Evidência executada

- `bash -n` concluiu sem erro para scripts de produção e testes.
- `tests/test_cpu.sh`, `test_dry_run.sh`, `test_gpu.sh`, `test_network.sh`, `test_packages.sh` e `test_storage.sh` passaram.
- Dois dry-runs consecutivos simulados com `--desktop gnome --profile desktop` produziram o mesmo plano após normalizar o timestamp: sem pacotes ou serviços duplicados.
- O mesmo teste revelou que o dry-run criou `existing-packages.txt`, `installed-packages.txt`, `modified-files.txt` e `services.txt` em `$XDG_STATE_HOME/arch-smart-postinstall/`.
- A matriz de GPU confirmou AMD, Intel, NVIDIA e combinações AMD+NVIDIA, Intel+NVIDIA e AMD+Intel. Também confirmou o falso AMD em Virtio e em dispositivo desconhecido.

## Arquitetura

O fluxo observável é `main` → `detect_all` → `build_plan` → `show_plan` → `confirm_plan` → `execute_plan` → `validate_plan` → `save_last_run`. `hardware/*.sh` apenas consulta o sistema; `lib/packages.sh` concentra `pacman`; `lib/executor.sh` concentra a habilitação de serviços. Não há `pacman` na detecção, `sudo` no planejamento nem `systemctl enable/disable` no planejamento.

Há duplicação leve de políticas de detecção entre detectores (por exemplo, verificações de `lspci`), mas não há alteração de sistema fora de executor/rollback. Isto não bloqueia o resultado de arquitetura.

## Segurança

Não foram encontrados comandos de formatação/particionamento (`fdisk`, `parted`, `mkfs`, `wipefs`, `sgdisk`), `dd`, alteração de GRUB/systemd-boot/EFI, `curl | bash`, download ou execução remota, AUR automático, `--noconfirm`, reboot, sysctl, parâmetros de kernel, overclock ou undervolt.

As operações de escrita encontradas são limitadas a logs/estado/backups, `pacman`, `systemctl enable/disable` e cópia de backup. Apesar disso, os problemas de GPU e remoção tornam a segurança geral reprovada.

## Detecção de hardware

| Detector | Fonte e dados | Limitações, ausência e falsos positivos |
| --- | --- | --- |
| CPU | `lscpu`: fabricante, modelo, CPUs lógicas e virtualização exposta pela CPU | Sem `lscpu`, retorna `OTHER`/campos vazios; não detecta microcode atual, frequência nem cores físicos. |
| GPU | `lspci -nnk`; opcionalmente `glxinfo` e `vulkaninfo` | Suporta múltiplas linhas, mas a expressão AMD é incorreta. Não extrai PCI ID/driver em uso apesar de pedir `-nnk`; VM/unknown sofrem falso positivo AMD. |
| RAM | `free -h` | Sem `free`, campos vazios; não informa arquitetura ou DIMMs. |
| Storage | `lsblk`, `findmnt` | Detecta resumo, raiz, filesystem e rotação; sem `lsblk`, o pipeline pode falhar sob `pipefail`. Não classifica individualmente HDD/SATA/NVMe/USB nem EFI/boot. |
| Network | `ip -br link` | Sem `ip`, retorna `nenhuma`; não registra chipset, fabricante ou driver. |
| Wi-Fi | `iw`, depois `lspci` | Alternativa razoável; `lspci` pode considerar controladora de rede não Wi-Fi conforme descrição. Resultado ainda não aparece no relatório. |
| Bluetooth | `bluetoothctl`, `lsusb`, `lspci` | Sem ferramentas, retorna não detectado. Pode confundir software instalado com hardware pois `bluetoothctl` sozinho é suficiente. |
| Laptop | bateria em `/sys/class/power_supply` | Sem bateria considera desktop; notebooks sem bateria/VM com BAT podem ser classificados incorretamente. |
| Virtualização | `systemd-detect-virt` | Sobrescreve máquina para VM quando disponível; ausência resulta `none`. |
| Boot | `/sys/firmware/efi` | UEFI/BIOS apenas; não toca no bootloader. |
| Monitor | DRM em `/sys/class/drm` | Somente conectividade; não informa fabricante, modelo, resolução ou taxa; falha de `find` pode propagar com `pipefail`. |
| Áudio | `systemctl --user`, existência de `pulseaudio` | Distingue PipeWire/Pulse/ALSA aproximado; não verifica se Pulse está funcional ou dispositivos ALSA. |

## GPUs

O planejador só chama drivers AMD, Intel e NVIDIA quando as flags respectivas estão ativas. Para AMD/Intel/NVIDIA e suas combinações, as flags esperadas foram observadas. NVIDIA não planeja `nvidia`, `nvidia-lts` ou outro módulo de kernel; apenas `nvidia-utils` (e `lib32-nvidia-utils` para gaming), acompanhado de aviso de compatibilidade. Isso atende à precaução de não assumir um módulo de kernel.

Entretanto, em `drivers/gpu.sh` a expressão `grep -Eqi 'AMD|ATI'` também encontra a sequência `ati` em `VGA compatible controller`. Portanto, entradas Virtio ou desconhecidas com a classe VGA são sinalizadas como AMD. O plano então inclui `mesa`, `vulkan-radeon` e `libva-mesa-driver` sem justificativa.

## Estado, backup, rollback e uninstall

`installed-packages.txt` é atualizado somente após `pacman -S` retornar sucesso e após `pacman -Q` confirmar cada pacote; pacotes encontrados antes são gravados em `existing-packages.txt`. Isso é correto para instalação interrompida.

Por outro lado, `init_state` é chamado antes do dry-run e cria arquivos persistentes. `state.json` e `last-run` só são escritos após validação, o que é consistente para execução que falha antes do fim.

`backup_file` usa `cp -a`, portanto preserva atributos quando a cópia funciona, e registra SHA-256, data e módulo. Não é chamado por módulos atuais de configuração. Ele não deduplica e armazena pelo basename. Rollback procura também somente pelo basename; dois caminhos diferentes como `/etc/a/app.conf` e `/etc/b/app.conf` podem restaurar a cópia errada. Arquivos criados não têm backup anterior e não são removidos no rollback.

Uninstall remove somente itens do registro, mas chama `pacman -Rns`. O `-s` pode remover dependências órfãs que não pertencem ao registro. Além disso, `remove_package` usa `|| true`, mascarando falha de `pacman`; a mesma supressão ocorre no `systemctl disable` do rollback. Uninstall não processa `services.txt`.

## Issues

### Critical issues

Nenhum comando crítico de destruição de disco, bootloader ou dados foi encontrado.

### High issues

1. **Detecção de GPU desconhecida/virtual como AMD** — `hardware/gpu.sh`, `detect_gpu`, linha 4. Risco: instalação de componentes AMD em hardware sem AMD, contrariando a seleção por hardware.
2. **Remoção agressiva e erro mascarado** — `lib/packages.sh`, `remove_package`, linha 17. Risco: `pacman -Rns` pode remover dependências não registradas e uma falha de remoção aparece como sucesso para o fluxo.
3. **Rollback escolhe backup por basename** — `lib/rollback.sh`, `rollback_run`, linha 6. Risco: restauração de arquivo incorreto em colisões de nome.

### Medium issues

1. **Dry-run grava estado persistente e logs** — `lib/core.sh`, `main`, linha 48; `lib/logger.sh` e `lib/state.sh`. Risco: viola o contrato de dry-run sem alterações de filesystem/estado.
2. **Backup não idempotente** — `lib/backup.sh`, `backup_file`, linhas 4–5. Risco: acúmulo infinito de backups e manifests para o mesmo estado.
3. **Rollback não lida com arquivos originalmente inexistentes** — `lib/backup.sh` e `lib/rollback.sh`. Risco: arquivos criados por módulos futuros permanecem após rollback.
4. **Detecção de armazenamento não degrada corretamente sem `lsblk`** — `hardware/storage.sh`, linha 2. Risco: falha crítica em vez de limitação informada.
5. **Detecção de Bluetooth pode ser falso positivo** — `hardware/bluetooth.sh`, linha 2. Risco: presença de `bluetoothctl` é tomada como presença de hardware.
6. **Distro não é realmente recusada por `/etc/os-release`** — `lib/core.sh`, `require_supported_system`, linhas 40–41. Risco: uma distribuição não Arch com um `pacman` no PATH recebe apenas aviso.

### Low issues

1. Relatório de hardware não mostra Wi-Fi, monitores, áudio, driver GPU, OpenGL/Vulkan, embora alguns dados sejam coletados.
2. `detect_machine` é heurístico e pode classificar notebook sem bateria como desktop.
3. `systemctl is-enabled` reduz vários estados a qualquer valor diferente de `enabled`; rollback trata todos como `disable`.
4. A documentação afirma que dry-run não cria log/estado, o que diverge do comportamento atual.

## Recommended fixes

| Arquivo | Função | Problema e risco | Correção recomendada |
| --- | --- | --- | --- |
| `hardware/gpu.sh` | `detect_gpu` | `ATI` casa com `compatible`; drivers AMD indevidos | Testar fornecedores/IDs PCI como campos delimitados, por exemplo `Advanced Micro Devices`/`AMD/ATI`, sem substring genérica. Adicionar testes Virtio/unknown. |
| `lib/packages.sh` | `remove_package` | `-Rns` remove órfãos e `|| true` oculta falha | Remover apenas o pacote registrado com política conservadora; propagar erro e atualizar registro somente depois do sucesso. |
| `lib/backup.sh`, `lib/rollback.sh` | `backup_file`, `rollback_run` | basename é ambíguo; arquivo criado não é revertido | Usar ID por caminho/hash no manifest, guardar caminho exato do backup e registrar explicitamente criação versus modificação. |
| `lib/core.sh`, `lib/logger.sh`, `lib/state.sh` | `main`, inicialização | dry-run escreve estado/log | Adiar inicialização persistente até a execução confirmada ou usar local temporário exclusivo para diagnóstico. |
| `hardware/storage.sh` | `detect_storage` | `lsblk` ausente pode abortar | Proteger o pipeline com `cmd lsblk`, fornecer valores vazios/limitação e testar a ausência. |
| `hardware/bluetooth.sh` | `detect_bluetooth` | binário instalado não prova hardware | Exigir fonte de hardware (`lsusb`, `lspci` ou sysfs) e tratar `bluetoothctl` apenas como capacidade de software. |
| `lib/core.sh` | `require_supported_system` | validação de distro permissiva | Validar `ID=arch`/`ID_LIKE` explicitamente e falhar quando não suportado, salvo uma lista explícita de compatíveis. |
| `lib/rollback.sh` | `uninstall_run` | uninstall não trata serviços | Planejar e restaurar/desabilitar apenas serviços que o projeto habilitou, com confirmação e registro atualizado. |

## Final verdict

**NEEDS FIXES**.

O projeto tem uma separação arquitetural útil e não contém operações destrutivas de disco/bootloader, mas não está pronto para um sistema real. A classificação errada de GPU, o comportamento de remoção e as garantias incompletas de dry-run/rollback devem ser corrigidos e testados em Arch Linux isolado antes de qualquer uso fora de testes.
