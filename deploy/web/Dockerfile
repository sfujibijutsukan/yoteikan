FROM golang:1.26-alpine AS build
WORKDIR /src
COPY web/ ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o /yoteikan-web .
FROM scratch
COPY --from=build /yoteikan-web /yoteikan-web
USER 65532:65532
ENV LISTEN_ADDR=:8080
EXPOSE 8080
ENTRYPOINT ["/yoteikan-web"]
