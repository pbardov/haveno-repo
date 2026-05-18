# Haveno Reto Debian Repository (GitHub Pages)

Этот репозиторий публикует APT-репозиторий из `.deb`-ассетов релизов:

- https://github.com/retoaccess1/haveno-reto/releases

Публикация выполняется через GitHub Actions workflow:

- `.github/workflows/publish-debian-repo.yml`

Собирающий скрипт:

- `scripts/build-debian-repo.sh`

## Как устроено хранение пакетов

- Ветка `master` хранит только код и workflow.
- Workflow использует `actions/cache` для каталога `site/pool/main`.
- На каждом запуске докачиваются только отсутствующие/поврежденные `.deb`, затем обновляются индексы APT и деплоится GitHub Pages.

## Подпись репозитория

Репозиторий подписывается GPG-ключом:

- генерируются `dists/stable/InRelease` и `dists/stable/Release.gpg`;
- публичный ключ публикуется в корне Pages как `haveno-repo-archive-keyring.gpg`.
- fingerprint ключа: `F5A8 9E48 5311 51F0 4618 C59E 1C47 1B69 D59D FD7C`.

Для workflow нужны GitHub Secrets:

- `APT_SIGNING_PRIVATE_KEY` — ASCII-armored приватный ключ (включая `-----BEGIN PGP PRIVATE KEY BLOCK-----`);
- `APT_SIGNING_PASSPHRASE` — passphrase ключа (только если ключ защищен паролем; иначе не нужен).

## Установка APT репозитория (актуально)

Для `https://pbardov.github.io/haveno-repo/`:

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://pbardov.github.io/haveno-repo/haveno-repo-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/haveno-repo-archive-keyring.gpg >/dev/null

gpg --show-keys --with-fingerprint --keyid-format LONG /etc/apt/keyrings/haveno-repo-archive-keyring.gpg

echo "deb [arch=amd64,arm64 signed-by=/etc/apt/keyrings/haveno-repo-archive-keyring.gpg] https://pbardov.github.io/haveno-repo/ stable main" \
  | sudo tee /etc/apt/sources.list.d/haveno-reto.list

sudo apt update
apt policy haveno
sudo apt install haveno
```

Ожидаемый fingerprint ключа:

```bash
F5A8 9E48 5311 51F0 4618 C59E 1C47 1B69 D59D FD7C
```

Для другого GitHub Pages URL подставьте свой домен/репозиторий:

```bash
deb [arch=amd64,arm64 signed-by=/etc/apt/keyrings/haveno-repo-archive-keyring.gpg] https://<YOUR_GITHUB_USER>.github.io/<YOUR_REPO_NAME>/ stable main
```
