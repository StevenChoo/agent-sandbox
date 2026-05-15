# macOS Notes

Podman on macOS runs inside a Linux VM managed by `podman machine`. This affects bind mounts.

## Install

```bash
brew install podman podman-compose
podman machine init
podman machine start
```

## Bind mount caveat

`podman machine` does not automatically expose your Mac home directory to the VM. You must explicitly mount it:

```bash
podman machine stop
podman machine set --volume /Users/johndoe:/Users/johndoe
podman machine start
```

Update `docker-compose.yml` to use `/Users/johndoe` as the source path, or set it via an env var.

Ask for updated cross-platform instructions when ready to make this seamless.
