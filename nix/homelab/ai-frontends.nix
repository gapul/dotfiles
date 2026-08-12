# Open WebUI and AnythingLLM, moved off the Mac mini on 2026-08-12.
#
# Both are frontends only: every model call goes back to the Mac mini over the
# tailnet (ollama for generation, the Ruri embedding server for retrieval), so
# neither needs to sit next to the GPU. On macOS they cost ~1.1G of resident
# memory and, worse, they were the two services whose published ports Apple
# container never forwarded for HTTP — each needed an ssh -L shim that had to be
# rebuilt every time the container IP moved. Here they are plain podman
# containers with working port publishing.
#
# The Minecraft server stays on the Mac mini: it wants the M4's single-thread
# speed, and its port is TCP, which Apple container does forward.
{
  lib,
  ...
}:

let
  # Same host as `macmini` in hosts/homeserver.nix. Tailnet, not LAN: the
  # 192.168.116.0/24 address of the Mac mini is not routable from here.
  macmini = "100.105.135.49";
in
{
  # Ports avoid 3000 (homepage) and 3003 (forgejo).
  virtualisation.oci-containers.containers."open-webui" = {
    image = "ghcr.io/open-webui/open-webui:main";
    environment = {
      "OLLAMA_BASE_URL" = "http://${macmini}:11434";
      # Retrieval embeds through ollama. Without this the image tries to pull
      # its bundled sentence-transformers model from HuggingFace on first boot
      # and hangs there; HF_HUB_OFFLINE makes that failure immediate instead.
      "RAG_EMBEDDING_ENGINE" = "ollama";
      "HF_HUB_OFFLINE" = "1";
      # No login screen. Reachable over the tailnet only, and this is what the
      # running instance has had since it was set up.
      "WEBUI_AUTH" = "False";
    };
    volumes = [
      "/var/lib/homelab/open-webui:/app/backend/data:rw"
    ];
    ports = [
      "3010:8080/tcp"
    ];
    log-driver = "journald";
    # Opted into the nightly image pull: stateless frontend, and podman rolls it back if the
    # new image fails to start.
    labels."io.containers.autoupdate" = "registry";
  };
  systemd.services."podman-open-webui" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
  };

  virtualisation.oci-containers.containers."anythingllm" = {
    image = "docker.io/mintplexlabs/anythingllm:latest";
    environment = {
      "STORAGE_DIR" = "/app/server/storage";
      "LLM_PROVIDER" = "ollama";
      "OLLAMA_BASE_PATH" = "http://${macmini}:11434";
      "OLLAMA_MODEL_PREF" = "gemma4:12b-it-qat";
      "OLLAMA_MODEL_TOKEN_LIMIT" = "8192";
      # Japanese embeddings come from the Ruri server on the Mac mini, spoken to
      # through the generic OpenAI shape. The key is a placeholder the server
      # ignores, not a secret.
      "EMBEDDING_ENGINE" = "generic-openai";
      "EMBEDDING_BASE_PATH" = "http://${macmini}:8900/v1";
      "EMBEDDING_MODEL_PREF" = "ruri-v3-310m";
      "EMBEDDING_MODEL_MAX_CHUNK_LENGTH" = "512";
      "GENERIC_OPEN_AI_EMBEDDING_API_KEY" = "sk-none";
      "VECTOR_DB" = "lancedb";
    };
    volumes = [
      "/var/lib/homelab/anythingllm:/app/server/storage:rw"
    ];
    ports = [
      "3011:3001/tcp"
    ];
    log-driver = "journald";
    labels."io.containers.autoupdate" = "registry";
  };
  systemd.services."podman-anythingllm" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
  };
}
