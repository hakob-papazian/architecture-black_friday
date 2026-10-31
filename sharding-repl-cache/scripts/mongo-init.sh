#!/bin/bash

###
# Инициализируем шардированный кластер с репликацией и заполняем БД
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

echo "==> 2. Инициализация replica set shard1 (shard1-1, shard1-2, shard1-3)"
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27018" },
    { _id: 2, host: "shard1-3:27018" }
  ]
});
while (!db.hello().primary) { sleep(1000); }
print("shard1: primary = " + db.hello().primary);
EOF

echo "==> 3. Инициализация replica set shard2 (shard2-1, shard2-2, shard2-3)"
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2-1:27019" },
    { _id: 1, host: "shard2-2:27019" },
    { _id: 2, host: "shard2-3:27019" }
  ]
});
while (!db.hello().primary) { sleep(1000); }
print("shard2: primary = " + db.hello().primary);
EOF

echo "==> 4. Добавление шардов в роутер, шардирование коллекции и заполнение данными"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.addShard("shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018");
sh.addShard("shard2/shard2-1:27019,shard2-2:27019,shard2-3:27019");
sh.shardCollection("somedb.helloDoc", { name: "hashed" });

use somedb
var docs = [];
for (var i = 0; i < 1000; i++) docs.push({ age: i, name: "ly" + i });
var res = db.helloDoc.insertMany(docs);
print("Всего документов: " + db.helloDoc.countDocuments());
EOF

echo "==> 5. Количество документов и реплик в каждом шарде"
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
use somedb
print("shard1: документов " + db.helloDoc.countDocuments() + ", реплик " + rs.status().members.length);
EOF

docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
use somedb
print("shard2: документов " + db.helloDoc.countDocuments() + ", реплик " + rs.status().members.length);
EOF
