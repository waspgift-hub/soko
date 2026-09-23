FROM node:20-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev --no-optional
COPY . .
ENV NODE_OPTIONS="--optimize-for-size --expose-gc"
# v2 entrypoint (Firestore/Redis stack) — the legacy Firestore `index.js` is
# frozen compatibility and must not be booted by fresh deployments.
EXPOSE 3000
CMD ["node", "src/index.js"]
