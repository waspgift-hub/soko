FROM node:20-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev --no-optional
COPY . .
EXPOSE 3000
ENV NODE_OPTIONS="--optimize-for-size --expose-gc"
CMD ["node", "index.js"]
