FROM hexpm/elixir:1.17.3-erlang-27.1.2-debian-bookworm-20241016 AS build
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
COPY config config
COPY lib lib
COPY assets assets
COPY priv priv
COPY rel rel
RUN mix compile
RUN mix assets.deploy
RUN mix release

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends libstdc++6 openssl ca-certificates locales curl \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i '/pt_BR.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
RUN useradd --create-home --shell /bin/sh dockd
WORKDIR /app
ENV LANG=pt_BR.UTF-8 LANGUAGE=pt_BR:pt LC_ALL=pt_BR.UTF-8 MIX_ENV=prod PHX_SERVER=true RELEASE_DISTRIBUTION=none
COPY --from=build --chown=dockd:dockd /app/_build/prod/rel/dockd ./
USER dockd
EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 CMD curl --fail http://127.0.0.1:4000/health || exit 1
CMD ["bin/dockd", "start"]
