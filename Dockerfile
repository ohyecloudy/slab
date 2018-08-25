FROM elixir:1.7.2

COPY . /app
WORKDIR /app

CMD ["script/server"]
