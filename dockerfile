
FROM ruby:3.4.1-alpine

LABEL maintainer="gilcierweb@gmail.com"

ENV RAILS_ENV development
ENV RAILS_SERVE_STATIC_FILES true
ENV RAILS_LOG_TO_STDOUT true
ENV APP_HOME /app
ENV BUNDLE_APP_CONFIG="$APP_HOME/.bundle"
ENV NODE_VERSION 16

RUN apk add --update \
      binutils-gold \
      bash \
      build-base \
      busybox \
      ca-certificates \
      curl \
      file \
      g++ \
      gcc \
      git \
      graphicsmagick \
      less \
      libstdc++ \
      libffi-dev \
      libc-dev \
      linux-headers \
      libxml2-dev \
      libxslt-dev \
      libgcrypt-dev \
      libffi-dev \
      libsodium-dev \
      make \
      netcat-openbsd \
      nodejs \
      openssl \
      pkgconfig \
      postgresql-dev \
      tzdata \
      openssh-client \
      rsync \
      yaml-dev \
      sqlite-dev \
      ruby-dev \
      zlib-dev \
      yarn

RUN ruby -v && node -v && yarn -v
RUN echo 'gem: --no-ri --no-rdoc' > ~/.gemrc
RUN mkdir -p $APP_HOME
WORKDIR $APP_HOME

COPY Gemfile Gemfile.lock ./
COPY package.json yarn.lock ./

RUN gem install bundler -v 2.3.12
RUN bundle check || bundle install
RUN yarn install --check-files

# Copia nosso código para dentro do container
COPY . $APP_HOME

RUN rm -f tmp/pids/server.pid

EXPOSE 3000

# Roda nosso servidor
#CMD ["bin/dev"]
