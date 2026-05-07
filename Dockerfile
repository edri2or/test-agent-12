FROM node:20-alpine AS builder

WORKDIR /app
COPY package*.json tsconfig.json ./
RUN npm ci --only=dev
COPY src/ ./src/
RUN npm run build:js

FROM node:20-alpine AS runtime

WORKDIR /app

# No runtime npm dependencies — copy compiled output only
COPY --from=builder /app/dist ./dist
COPY src/agent/skills/SKILL.md ./dist/agent/skills/SKILL.md

RUN addgroup -S agent && adduser -S agent -G agent
USER agent

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', r => process.exit(r.statusCode === 200 ? 0 : 1))"

CMD ["node", "dist/agent/index.js"]
