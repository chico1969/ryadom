FROM node:24-alpine@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts --no-fund && npm cache clean --force
COPY --chown=node:node server.mjs ./
COPY --chown=node:node public ./public
ENV NODE_ENV=production PORT=9000 NODE_OPTIONS=--max-old-space-size=128
USER node
EXPOSE 9000
CMD ["node", "server.mjs"]
