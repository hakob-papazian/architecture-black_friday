# pymongo-api: шардирование, репликация и кеширование

Проектная работа 4 спринта: онлайн-магазин «Мобильный мир».

## Структура репозитория

| Путь                   | Что внутри                                                                  |
|------------------------|-----------------------------------------------------------------------------|
| `task1.drawio`         | схемы решения; итоговая схема — вкладка **«5. CDN»**                         |
| `mongo-sharding/`      | задание 2: MongoDB с шардированием (2 шарда)                                 |
| `mongo-sharding-repl/` | задание 3: шардирование + репликация (по 3 реплики на шард)                  |
| `sharding-repl-cache/` | задание 4: шардирование + репликация + кеширование в Redis — **итоговое решение** |
| `compose.yaml`         | исходный стенд: приложение и одна нода MongoDB                               |

Схемы в `task1.drawio` (открываются в [draw.io](https://app.diagrams.net)):

1. Шардирование — задание 1.
2. Репликация — задание 1.
3. Кеширование — задание 1.
4. API Gateway + Consul — задание 5.
5. CDN — задание 6, итоговая схема со всеми изменениями.

## Как запустить итоговое решение

Нужны Docker с Docker Compose (минимум 2 CPU и 4 ГБ ОЗУ) и bash (на Windows — Git Bash или WSL).

```shell
cd sharding-repl-cache
```

Запускаем MongoDB (config server, 2 шарда по 3 реплики, mongos), Redis и приложение `kazhem/pymongo_api:1.0.0`:

```shell
docker compose up -d
```

Проверяем, что все сервисы запущены:

```shell
docker compose ps
```

Инициализируем replica set'ы и шардирование, заполняем БД (`somedb.helloDoc`, 1000 документов):

```shell
./scripts/mongo-init.sh
```

В конце скрипт выводит общее количество документов, а также количество документов и реплик в каждом шарде. Пошаговое описание команд — в [sharding-repl-cache/README.md](sharding-repl-cache/README.md).

## Как проверить

Откройте в браузере http://localhost:8080. Приложение вернёт JSON с информацией о MongoDB и кеше:

- `"mongo_topology_type": "Sharded"`;
- `"shards"` — оба шарда со всеми репликами:
  `"shard1": "shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018"`,
  `"shard2": "shard2/shard2-1:27019,shard2-2:27019,shard2-3:27019"`;
- `"collections": {"helloDoc": {"documents_count": 1000}}`;
- `"cache_enabled": true`.

Кеширование: первый запрос к `/helloDoc/users` выполняется дольше секунды, повторные (в течение 60 секунд) — быстрее 100 мс:

```shell
for i in 1 2 3; do
  curl -s -o /dev/null -w "запрос $i: %{time_total} с\n" http://localhost:8080/helloDoc/users
done
```

Количество документов и реплик в каждом шарде можно посмотреть отдельно — команды приведены в [sharding-repl-cache/README.md](sharding-repl-cache/README.md#как-проверить).

Список эндпоинтов (swagger): http://localhost:8080/docs

Остановить стенд и удалить данные:

```shell
docker compose down -v
```

## Промежуточные варианты

`mongo-sharding` и `mongo-sharding-repl` запускаются так же: `docker compose up -d` и `./scripts/mongo-init.sh` в соответствующей директории. Подробности — в их README. Все варианты публикуют порт 8080, поэтому одновременно может работать только один из них.

## Исходный стенд

Приложение и одна нода MongoDB, без шардирования и репликации:

```shell
docker compose up -d
./scripts/mongo-init.sh
```

Приложение будет доступно на http://localhost:8080 (на виртуальной машине — http://<ip виртуальной машины>:8080, белый IP можно узнать командой `curl --silent http://ifconfig.me`).
