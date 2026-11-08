# The Firestore emulator is a Java process, so a JRE is required alongside
# the Node-based firebase-tools CLI.
FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    default-jre-headless \
    && rm -rf /var/lib/apt/lists/*

# Exact, so every run (the dev stack, the API's tests, the rules tests and the
# release's rules and index deploy) uses the same emulator and CLI.
RUN npm install -g firebase-tools@13.35.1

WORKDIR /workspace

EXPOSE 4000 8080 9099

CMD ["firebase", "emulators:start", \
     "--project", "map-my-friends-local", \
     "--only", "auth,firestore"]
