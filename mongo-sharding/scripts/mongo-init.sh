#!/bin/bash

###
# Инициализируем шардированный кластер и заполняем БД
###

set -e
cd "$(dirname "$0")/.."

echo "==> 1. Инициализация сервера конфигурации"
docker compose exec -T configSrv mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27017" }]
});
while (!db.hello().isWritablePrimary) { sleep(1000); }
print("configSrv: PRIMARY");
EOF

echo "==> 2. Инициализация шарда shard1"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1",
  members: [{ _id: 0, host: "shard1:27018" }]
});
while (!db.hello().isWritablePrimary) { sleep(1000); }
print("shard1: PRIMARY");
EOF

echo "==> 3. Инициализация шарда shard2"
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [{ _id: 0, host: "shard2:27019" }]
});
while (!db.hello().isWritablePrimary) { sleep(1000); }
print("shard2: PRIMARY");
EOF

echo "==> 4. Добавление шардов в роутер, шардирование коллекции и заполнение данными"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.addShard("shard1/shard1:27018");
sh.addShard("shard2/shard2:27019");
sh.shardCollection("somedb.helloDoc", { name: "hashed" });

use somedb
var docs = [];
for (var i = 0; i < 1000; i++) docs.push({ age: i, name: "ly" + i });
var res = db.helloDoc.insertMany(docs);
print("Всего документов: " + db.helloDoc.countDocuments());
EOF

echo "==> 5. Количество документов на каждом шарде"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
print("shard1: " + db.helloDoc.countDocuments());
EOF

docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
use somedb
print("shard2: " + db.helloDoc.countDocuments());
EOF
