# Stage 1: Build
FROM node:22-alpine AS builder

WORKDIR /app

COPY package.json package-lock.json ./

ARG NPM_PRIVATE_REGISTRY_URL
    
RUN npm config set @loash-industries:registry ${NPM_PRIVATE_REGISTRY_URL}
RUN --mount=type=secret,id=GH_AUTH_TOKEN \
    npm config set ${NPM_PRIVATE_REGISTRY_URL#http*:}:_authToken "$(cat /run/secrets/GH_AUTH_TOKEN)" \
    && echo "always-auth=true" >> ~/.npmrc

RUN npm ci

COPY . .
RUN npm run build

# Stage 2: Serve
FROM caddy:2-alpine

COPY --from=builder /app/dist /srv
COPY Caddyfile /etc/caddy/Caddyfile

EXPOSE 80
