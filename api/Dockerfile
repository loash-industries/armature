FROM node:22.15-slim AS builder

WORKDIR /usr/src

COPY package.json yarn.lock* package-lock.json* ./

RUN npm install

COPY . .

RUN npm run build

RUN npm prune --production

FROM node:22.15-slim AS run

WORKDIR /usr/src

USER node
EXPOSE 3000

ENV PORT=3000
ENV LOG_LEVEL=info
ENV NODE_ENV=production

COPY --from=builder --chown=node:node /usr/src/dist ./dist
COPY --from=builder --chown=node:node /usr/src/package.json ./
COPY --from=builder --chown=node:node /usr/src/node_modules ./node_modules

CMD ["node", "dist/index.js"]
