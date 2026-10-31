# sharding-repl-cache

MongoDB с шардированием на два шарда и репликацией (каждый шард — replica set из трёх нод) плюс кеширование ответов приложения в Redis (вариант 3 схемы из `task1.drawio`).

| Сервис                           | Роль                                              | Порт  |
|----------------------------------|---------------------------------------------------|-------|
| `configSrv`                      | сервер конфигурации (replica set `config_server`) | 27017 |
| `shard1-1`, `shard1-2`, `shard1-3` | шард 1, replica set `shard1`                    | 27018 |
| `shard2-1`, `shard2-2`, `shard2-3` | шард 2, replica set `shard2`                    | 27019 |
| `mongos_router`                  | роутер `mongos`, точка входа для приложения       | 27020 |
| `redis`                          | кеш ответов приложения                            | 6379  |
| `pymongo_api`                    | приложение                                        | 8080  |

Коллекция `somedb.helloDoc` шардируется по ключу `{ name: "hashed" }`.

Кеширование включается переменной окружения `REDIS_URL: "redis://redis:6379"` у сервиса `pymongo_api`. Кешируется эндпоинт `GET /<collection_name>/users`, время жизни записи в кеше — 60 секунд.

## Как запустить

Все команды выполняются из директории `sharding-repl-cache`.

Запускаем MongoDB и приложение:

```shell
docker compose up -d
```

Инициализируем репликацию и шардирование, заполняем БД данными (1000 документов):

```shell
./scripts/mongo-init.sh
```

Скрипт выполняет шаги, описанные ниже. Их можно выполнить и вручную.

### 1. Инициализация сервера конфигурации

```shell
docker compose exec -T configSrv mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27017" }]
});
EOF
```

### 2. Настройка репликации для каждого шарда

Replica set инициализируется командой на любой из его нод. В списке `members` перечисляются все три реплики шарда; после инициализации они сами выберут primary, остальные две станут secondary.

Шард 1:

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27018" },
    { _id: 2, host: "shard1-3:27018" }
  ]
});
EOF
```

Шард 2:

```shell
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2-1:27019" },
    { _id: 1, host: "shard2-2:27019" },
    { _id: 2, host: "shard2-3:27019" }
  ]
});
EOF
```

Выбор primary занимает несколько секунд. Прежде чем переходить к следующему шагу, убедитесь, что в каждом replica set есть `PRIMARY` (см. «Количество реплик» ниже).

### 3. Добавление шардов в роутер и шардирование коллекции

Шард добавляется как replica set: в строке указывается имя replica set и все его ноды.

```shell
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.addShard("shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018");
sh.addShard("shard2/shard2-1:27019,shard2-2:27019,shard2-3:27019");
sh.shardCollection("somedb.helloDoc", { name: "hashed" });
EOF
```

### 4. Заполнение данными

```shell
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({ age: i, name: "ly" + i });
EOF
```

## Как проверить

### Приложение

Откройте в браузере http://localhost:8080. В ответе должны быть:

- `"mongo_topology_type": "Sharded"`;
- в `shards` — оба шарда со всеми репликами:
  `"shard1": "shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018"`,
  `"shard2": "shard2/shard2-1:27019,shard2-2:27019,shard2-3:27019"`;
- в `collections.helloDoc.documents_count` — общее количество документов (1000).

Общее количество документов также доступно на http://localhost:8080/helloDoc/count.

Список эндпоинтов (swagger): http://localhost:8080/docs

### Количество документов в каждом шарде

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Сумма по шардам равна общему количеству документов. Благодаря репликации на любой ноде шарда (например, `shard1-3`) количество документов будет тем же.

### Количество реплик

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.forEach(m => print(m.name + " " + m.stateStr))
EOF

docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
rs.status().members.forEach(m => print(m.name + " " + m.stateStr))
EOF
```

В каждом шарде должно быть три реплики: одна `PRIMARY` и две `SECONDARY`.

### Кеширование

На http://localhost:8080 должно быть `"cache_enabled": true`.

Вызовите эндпоинт `/helloDoc/users` несколько раз подряд и сравните время ответа:

```shell
for i in 1 2 3; do
  curl -s -o /dev/null -w "запрос $i: %{time_total} с\n" http://localhost:8080/helloDoc/users
done
```

Первый запрос идёт в MongoDB и занимает больше секунды. Второй и последующие (в течение 60 секунд) отдаются из Redis быстрее чем за 100 мс.

Ключи кеша в Redis:

```shell
docker compose exec -T redis redis-cli --scan --pattern "api:cache:*"
```

## Как остановить

```shell
docker compose down -v
```
