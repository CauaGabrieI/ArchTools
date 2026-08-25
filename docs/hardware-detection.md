# Detecção

CPU usa `lscpu`; GPUs usam `lspci -nnk` e preservam todas as controladoras; memória usa `free`; armazenamento usa `lsblk` e `findmnt`; virtualização usa `systemd-detect-virt`; monitores usam DRM. A ausência dessas ferramentas reduz a informação, não inicia instalação nem interrompe a execução.
