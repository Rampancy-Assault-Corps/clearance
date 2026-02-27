FROM eclipse-temurin:21-jre

WORKDIR /app

RUN groupadd --system racbot && useradd --system --gid racbot racbot

COPY build/libs/RACBot-*.jar /app/RACBot.jar
COPY config/bot.toml.example /app/config/bot.toml.example

RUN mkdir -p /app/data /app/config && chown -R racbot:racbot /app

USER racbot

VOLUME ["/app/data", "/app/config"]

ENTRYPOINT ["java", "-jar", "/app/RACBot.jar"]
