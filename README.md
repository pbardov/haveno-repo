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

Для workflow нужны GitHub Secrets:

- `APT_SIGNING_PRIVATE_KEY` — ASCII-armored приватный ключ (включая `-----BEGIN PGP PRIVATE KEY BLOCK-----`);
- `APT_SIGNING_PASSPHRASE` — passphrase ключа (если ключ защищен паролем).

## Подключение репозитория

После включения GitHub Pages для этого репозитория:

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://<YOUR_GITHUB_USER>.github.io/<YOUR_REPO_NAME>/haveno-repo-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/haveno-repo-archive-keyring.gpg >/dev/null

echo "deb [signed-by=/etc/apt/keyrings/haveno-repo-archive-keyring.gpg] https://<YOUR_GITHUB_USER>.github.io/<YOUR_REPO_NAME>/ stable main" \
  | sudo tee /etc/apt/sources.list.d/haveno-reto.list
sudo apt update
```

Если вы используете этот репозиторий `pbardov/haveno-repo`, строка будет:

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://pbardov.github.io/haveno-repo/haveno-repo-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/haveno-repo-archive-keyring.gpg >/dev/null

echo "deb [signed-by=/etc/apt/keyrings/haveno-repo-archive-keyring.gpg] https://pbardov.github.io/haveno-repo/ stable main" \
  | sudo tee /etc/apt/sources.list.d/haveno-reto.list
sudo apt update
```
