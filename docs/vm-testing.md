# Validação em VM Arch Linux

Use uma VM descartável. Não valide a primeira execução em um computador com dados importantes.

## VM e snapshot limpo

Crie uma VM com UEFI, 2 vCPUs, 4 GB de RAM, 30 GB de disco virtual e rede NAT. VirtualBox, QEMU/KVM e VMware são adequados. Instale uma imagem oficial atual do Arch Linux, execute o procedimento normal do Arch Wiki, crie um usuário com `sudo` e configure rede funcional.

Após o primeiro boot, atualize a VM, instale o mínimo para obter o projeto e executar testes (`git`, `base-devel` e, opcionalmente, `shellcheck`), clone/cop ie o projeto e crie um snapshot chamado, por exemplo, `arch-clean`. Esse snapshot é o ponto de retorno antes de cada cenário que modifica pacotes ou serviços.

## Testes sem alteração

No diretório do projeto, execute:

```bash
for test in tests/test_*.sh; do bash "$test"; done
bash -n install.sh lib/*.sh hardware/*.sh drivers/*.sh desktop/*.sh profiles/*.sh services/*.sh
shellcheck $(find . -name '*.sh' -type f) # se instalado
./install.sh --detect-only
./install.sh --desktop minimal --profile minimal --dry-run
./install.sh --desktop gnome --profile gaming --dry-run
```

Os testes usam mocks de `pacman`, `sudo` e `systemctl` quando podem atingir o fluxo principal. Os mocks recusam mutações. A detecção pode consultar o hardware e systemd reais apenas em modo de leitura; dry-run não deve criar `~/.local/state/arch-smart-postinstall` nem arquivos em `logs/`.

## Cenário de instalação

Restaure `arch-clean`. Primeiro execute um dry-run e revise integralmente o plano. Se ele estiver correto, escolha um cenário pequeno, por exemplo:

```bash
./install.sh --desktop minimal --profile minimal
```

Confirme somente depois de revisar os pacotes e serviços. Após a execução, valide `./install.sh --list-changes`, os serviços mostrados no plano e o conteúdo de `~/.local/state/arch-smart-postinstall/`.

## Rollback, uninstall e idempotência

Ainda na mesma VM de teste:

```bash
./install.sh --rollback
./install.sh --list-changes
./install.sh --uninstall
./install.sh --desktop minimal --profile minimal # segundo run para idempotência
```

Revise cada plano e confirmação. Não use `--yes` na primeira validação. Depois de registrar o resultado, restaure o snapshot `arch-clean`; isso devolve pacotes, serviços e estado ao ponto conhecido, sem depender do rollback para limpar a VM.

## Critério de parada

Pare e restaure o snapshot se o plano incluir driver de GPU incompatível, serviço inesperado, pacote não solicitado, alteração de disco/bootloader, ou se uma validação falhar. Registre o log correspondente antes de restaurar.
