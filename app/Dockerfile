# syntax=docker/dockerfile:1
# Workshop image for Upwind Shift Left SCA (Log4j 2.14.1 / CVE-2021-44228).

FROM maven:3.9-eclipse-temurin-11 AS build
WORKDIR /src
COPY pom.xml .
COPY src ./src
RUN mvn -B -DskipTests package \
 && JAR=$(ls target/traditional-jay-*.jar | head -1) \
 && cp "$JAR" /src/app.jar

FROM eclipse-temurin:11-jre
WORKDIR /app
COPY --from=build /src/app.jar /app/app.jar
EXPOSE 8080
USER 10001
ENTRYPOINT ["java", "-jar", "/app/app.jar", "--server.port=8080"]
