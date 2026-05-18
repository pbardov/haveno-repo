# Haveno Reto Debian Repository (GitHub Pages)

Этот репозиторий публикует APT-репозиторий из `.deb`-ассетов релизов:

- https://github.com/retoaccess1/haveno-reto/releases

Публикация выполняется через GitHub Actions workflow:

- `.github/workflows/publish-debian-repo.yml`

Собирающий скрипт:

- `scripts/build-debian-repo.sh`

## Как устроено хранение пакетов

- Ветка `master` хранит только код и workflow.
- Ветка `site-upload` хранит каталог `site/` с уже скачанными `.deb`.
- Workflow на каждом запуске синхронизирует `site-upload` с `master`, докачивает только отсутствующие пакеты, обновляет индексы APT и пушит изменения обратно в `site-upload`.

## Подключение репозитория

После включения GitHub Pages для этого репозитория:

```bash
echo "deb [trusted=yes] https://<YOUR_GITHUB_USER>.github.io/<YOUR_REPO_NAME>/ stable main" | sudo tee /etc/apt/sources.list.d/haveno-reto.list
sudo apt update
```

Если вы используете этот репозиторий `pbardov/haveno-repo`, строка будет:

```bash
echo "deb [trusted=yes] https://pbardov.github.io/haveno-repo/ stable main" | sudo tee /etc/apt/sources.list.d/haveno-reto.list
sudo apt update
```
