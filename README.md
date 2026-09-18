# TP Docker : Application 3-tier

## Structure du projet

```
tp1/
  .env                        identifiants (POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD), ignoré par git
  .gitignore
  docker-compose.yml          orchestre les 3 services
  Dockerfile                  image de la base de données
  init-scripts/
    01-CreateScheme.sql       création des tables
    02-InsertData.sql         données de test
  Backend API/
    Main.java / Main.class / Dockerfile   étape hello world (Basics)
    simpleapi/
      Dockerfile              build multistage (JDK -> JRE)
      pom.xml
      src/                    API Spring Boot (simple-api-student)
  HTTP Server/
    Dockerfile
    index.html
    httpd.conf                config Apache + reverse proxy vers le backend
```

`.env` (racine du projet, non versionné) :

```
POSTGRES_DB=db
POSTGRES_USER=usr
POSTGRES_PASSWORD=pwd
```

Ces trois variables sont lues par le conteneur `database` (initialisation Postgres) et par le conteneur `backend` (`application.yml` les référence via `${...}` pour se connecter à la base), que ce soit lancé manuellement avec `--env-file` ou via `docker-compose.yml` avec `env_file`.

Les 3 tiers : `database` (Postgres) <- `backend` (Spring Boot, Java 21) <- `httpd` (Apache, reverse proxy, seul point d'entrée exposé sur le port 80).

## Commandes de lancement

### 1. Base de données

```
docker network create app-network
docker build -t database .
docker run -d --name database --network app-network --env-file .env -v pgdata:/var/lib/postgresql/data -p 5432:5432 database
```

### 2. Backend API

```
cd "Backend API/simpleapi"
docker build -t backend-api .
docker run -d --name backend-api --network app-network --env-file ../../.env -p 8080:8080 backend-api
```

### 3. HTTP Server

```
cd "HTTP Server"
docker build -t http-server .
docker run -d --name http-server --network app-network -p 80:80 http-server
```

### 4. Tout orchestrer avec docker-compose (méthode recommandée)

Depuis la racine `tp1/` :

```
docker compose up -d --build
docker compose ps
```

Test : `http://localhost/departments/IRC/students`

Autres commandes utiles : `docker compose logs -f <service>`, `docker compose stop`/`start`, `docker compose down` (garde les volumes), `docker compose down -v` (supprime aussi les volumes), `docker compose build`.

### 5. Publier sur Docker Hub

```
docker login
docker tag database USERNAME/tp1-database:1.0
docker tag backend-api USERNAME/tp1-backend-api:1.0
docker tag http-server USERNAME/tp1-http-server:1.0
docker push USERNAME/tp1-database:1.0
docker push USERNAME/tp1-backend-api:1.0
docker push USERNAME/tp1-http-server:1.0
```

*(remplacer USERNAME par le compte Docker Hub)*

Explication ligne par ligne :
- `FROM eclipse-temurin:21-jdk-alpine AS myapp-build` : image avec JDK complet, nommée `myapp-build`, dédiée à la compilation.
- `ENV MYAPP_HOME=/opt/myapp` : variable réutilisée pour le chemin de travail.
- `WORKDIR $MYAPP_HOME` : dossier de travail dans le conteneur.
- `RUN apk add --no-cache maven` : installe Maven sans garder le cache apk.
- `COPY pom.xml .` puis `COPY src ./src` : copie les fichiers du projet Maven.
- `RUN mvn package -DskipTests` : compile et empaquette en `.jar` (tests ignorés).
- `FROM eclipse-temurin:21-jre-alpine` : nouvelle étape, image finale, runtime seul.
- `COPY --from=myapp-build ... myapp.jar` : récupère uniquement le `.jar` produit, rien d'autre.
- `ENTRYPOINT ["java", "-jar", "myapp.jar"]` : commande lancée au démarrage.


**1-8 Document your docker-compose file.**

```yaml
services:
  database:
    build: .
    image: database
    container_name: database
    env_file:
      - .env
    volumes:
      - pgdata:/var/lib/postgresql/data
    networks:
      - app-network
    restart: unless-stopped

  backend:
    build: "./Backend API/simpleapi"
    image: backend-api
    container_name: backend-api
    env_file:
      - .env
    depends_on:
      - database
    networks:
      - app-network
    restart: unless-stopped

  httpd:
    build: "./HTTP Server"
    image: http-server
    container_name: http-server
    ports:
      - "80:80"
    depends_on:
      - backend
    networks:
      - app-network
    restart: unless-stopped

networks:
  app-network:
    name: app-network

volumes:
  pgdata:
```

Seul `httpd` expose un port sur l'hôte (`database` et `backend` restent internes, joignables uniquement via `app-network`). `env_file` centralise les secrets. `depends_on` ordonne le démarrage. `restart: unless-stopped` relance un conteneur qui crashe. `pgdata` persiste les données de la base indépendamment des conteneurs.

## Bonus – Segmentation réseau (protéger la base de données)

Avec un seul réseau `app-network` partagé par les 3 conteneurs, `httpd` pouvait techniquement joindre directement `database`, alors qu'il n'en a aucun besoin (seul `backend` doit lui parler). Pour réduire la surface d'attaque, la base est isolée sur un réseau séparé, invisible depuis `httpd`.

**Deux réseaux au lieu d'un :**
- `back-network` : `database` <-> `backend` uniquement.
- `front-network` : `backend` <-> `httpd` uniquement.
- `backend` est le seul conteneur présent sur les deux réseaux (il doit parler à la base et être joignable par httpd) ; `database` n'est présente que sur `back-network`.

```yaml
networks:
  back-network:
    name: back-network
  front-network:
    name: front-network
```

(voir le fichier complet en question 1-8 ci-dessus)

**Vérification** : la résolution DNS entre conteneurs prouve l'isolation.

```
$ docker exec -it backend-api getent hosts database
172.20.0.2        database  database

$ docker exec -it backend-api getent hosts http-server
172.19.0.3        http-server  http-server
```

Le backend résout bien les deux noms, avec des IP sur deux sous-réseaux différents (`172.20.x.x` et `172.19.x.x`) confirmation qu'il est bien membre des deux réseaux.

```
$ docker exec -it http-server getent hosts database
(aucune sortie : la résolution échoue)
```

Depuis `httpd`, `database` ne résout à rien : les deux conteneurs ne partagent plus aucun réseau, `httpd` ne peut donc plus atteindre la base, même par erreur ou en cas de compromission du serveur web. L'application reste pleinement fonctionnelle (`http://localhost/departments/IRC/students` répond normalement) car le seul chemin nécessaire, `httpd → backend → database`, passe bien par les deux réseaux via `backend`.



