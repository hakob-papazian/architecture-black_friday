# mongo-sharding

MongoDB с шардированием на два шарда (вариант 1 схемы из `task1.drawio`).

| Сервис          | Роль                                   | Порт  |
|-----------------|----------------------------------------|-------|
| `configSrv`     | сервер конфигурации (replica set `config_server`) | 27017 |
| `shard1`        | шард 1 (replica set `shard1`)          | 27018 |
| `shard2`        | шард 2 (replica set `shard2`)          | 27019 |
| `mongos_router` | роутер `mongos`, точка входа для приложения | 27020 |
| `pymongo_api`   | приложение                             | 8080  |

Коллекция `somedb.helloDoc` шардируется по ключу `{ name: "hashed" }`.

## Как запустить

Все команды выполняются из директории `mongo-sharding`.

Запускаем MongoDB и приложение:

```shell
docker compose up -d
```

Инициализируем шардирование и заполняем БД данными (1000 документов):

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

### 2. Инициализация шардов

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({ _id: "shard1", members: [{ _id: 0, host: "shard1:27018" }] });
EOF

docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
rs.initiate({ _id: "shard2", members: [{ _id: 0, host: "shard2:27019" }] });
EOF
```

### 3. Добавление шардов в роутер и шардирование коллекции

```shell
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.addShard("shard1/shard1:27018");
sh.addShard("shard2/shard2:27019");
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
- в `shards` — оба шарда: `shard1` и `shard2`;
- в `collections.helloDoc.documents_count` — общее количество документов (1000).

Общее количество документов также доступно на http://localhost:8080/helloDoc/count.

Список эндпоинтов (swagger): http://localhost:8080/docs

### Количество документов в каждом шарде

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Сумма по шардам равна общему количеству документов. Распределение по шардам через роутер:

```shell
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution()
EOF
```

## Как остановить

```shell
docker compose down -v
```
