# Gentoo Linux stage4 Dockerfile

This Dockerfile allow to bootstrap a pristine, minimal and optimized gentoo image. It fetches the latest stage3 tarball, portage and recompiles the whole system using GCC `-march=native -Os` optimizations.

**Recompilinig the whole system twice takes quite some time (~4h on my MacBook Pro using 8 threads: `MAKEOPTS="-j8"`), so it might not be what you want.**

If you have compatible hardware, you can fetch a ready to use image from my Docker Hub repo: https://cloud.docker.com/u/gfrancesco11/repository/docker/gfrancesco11/gentoo-stage4

Images on the Docker Hub have been compiled for an [Intel i9-8950HK CPU](https://ark.intel.com/content/www/us/en/ark/products/134903/intel-core-i9-8950hk-processor-12m-cache-up-to-4-80-ghz.html), using these GCC `-march=native -Os` optimizations.

Some parts of the Dockerfile come from the official Gentoo dockerfile [gentoo/gentoo-docker-images](https://github.com/gentoo/gentoo-docker-images).

# Requirements, testing and development setup

I tested the Dockerfile using Docker Desktop v2.1.0.3 for MacOS, with Docker Engine v19.03.2, YMMV.

Requirements:
1. You need to enable **Experimental features** in the docker daemon, since the Dockerfile needs to be built using [`buildx`](https://docs.docker.com/buildx/working-with-buildx/) that extends the docker command with the full support of the features provided by [Moby BuildKit](https://github.com/moby/buildkit) builder toolkit.
2. The number of CPUs you allocate do the Docker daemon should be greater than the number of threads you use in GCC to emerge and compile the gentoo packages, otherwise compilation will fail. By default the Dockerfile uses 8 threads, but you can change this number at build time.
3. Some of the compilation is performed in RAM, I allocated 10 GiB to my Docker daemon, but it might work with less.

# Build
1. Create the Buildkit builder

   - `docker buildx create --use --name insecure-builder --buildkitd-flags '--allow-insecure-entitlement security.insecure'`
2. Choose your build-time customization options:

   - `--build-arg SUFFIX="-nomultilib"` see [gentoo/gentoo-docker-images](https://github.com/gentoo/gentoo-docker-images#inventory) for the full list of options, I only tested `-nomultilib` with `ARCH=amd64` (which is the default ARCH).

   - `--build-arg CPU_N=4` number of threads used by GCC to compile the packages, the default is `8`.
   
   - `--cache-to=type=local,dest=gentoo_cache` saves the build cache into the `gentoo_cache` folder.
   
   - `--cache-from=type=local,src=gentoo_cache` fetches the build cache from the `gentoo_cache` folder, **remove this option on your first build, since you'll have no cache from previous builds**.
   
3.  Build the image:

```
docker buildx build \
--build-arg SUFFIX="-nomultilib" \
--build-arg CPU_N=4 \
--allow security.insecure \
--cache-to=type=local,dest=gentoo_cache \
--cache-from=type=local,src=gentoo_cache \
--load -t your_user/gentoo-stage4:latest
-f gentoo-stage4.Dockerfile .
```

# Result
The final image is size-optimized, a `-nomultilib` build is less than 900 MiB and does not include the portage tree.

# Run the container
To run the container in interactive mode you can use:

`docker run -t -i --cap-add=SYS_ADMIN --cap-add=NET_ADMIN --cap-add=SYS_PTRACE --rm your_user/gentoo-stage4`

The `--cap-add` statements are required to prevent permission errors/warnings when emerging packages and to be able to emerge some packages like _sys-libs/glibc_, which will otherwise fail to compile. If your application runs without errors/warnings you can remove them.

If you need the portage tree in your container you can mount it as a volume from the official `gentoo/portage` image:

```
docker create --name portage_c gentoo/portage
docker run -t -i --rm --volumes-from portage_c your_user/gentoo-stage4:latest
```
# FAQ
**1. What's the difference between this project and the official [gentoo/gentoo-docker-images](https://github.com/gentoo/gentoo-docker-images)?**
   - The official [gentoo/gentoo-docker-images](https://github.com/gentoo/gentoo-docker-images) use a wrapper build script, while I preferred to avoid additional code outside the Dockerfile. The `gentoo-stage4` images are pre-configured and entirely recompiled with GCC optimizations, that is possible thanks to BuildKit.
