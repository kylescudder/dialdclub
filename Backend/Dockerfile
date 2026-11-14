FROM oven/bun:1.4.4@sha256:1d22548f177f4ff38e0c15baa3c2c46c6c2060ba2d1bc573bb4720b407548f1d AS build
WORKDIR /app
ENV HUSKY=0 CI=true
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile
COPY src ./src
COPY scripts ./scripts
COPY drizzle ./drizzle
COPY tsconfig.json ./
RUN bun run typecheck && bun run build

FROM oven/bun:1.4.4@sha256:1d22548f177f4ff38e0c15baa3c2c46c6c2060ba2d1bc573bb4720b407548f1d
WORKDIR /app
ENV NODE_ENV=production HUSKY=0
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile --production --ignore-scripts
COPY --from=build /app/dist ./dist
COPY --from=build /app/scripts ./scripts
COPY --from=build /app/src ./src
COPY --from=build /app/drizzle ./drizzle
COPY deploy/verify.ts ./deploy/verify.ts
ARG DIALD_REVISION=development
ENV DIALD_REVISION=${DIALD_REVISION}
LABEL org.opencontainers.image.revision=${DIALD_REVISION}
USER 1000:1000
EXPOSE 3147
CMD ["bun", "dist/index.js"]
