FROM node:20-slim
WORKDIR /app
COPY soko_langu/server/package*.json ./
RUN npm ci --omit=dev
COPY soko_langu/server/ .
EXPOSE 8080
CMD ["node", "index.js"]
