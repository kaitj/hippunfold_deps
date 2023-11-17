# Stage: requirements
FROM python:3.9-slim-bullseye as requirements
ENV DEBIAN_FRONTEND="noninteractive" 
RUN apt-get update -qq \
    && apt-get install -y -q --no-install-recommends \
    bc \
    build-essential \
    bzip2 \
    ca-certificates \
    cmake \
    cmake-curses-gui \
    curl \
    default-jre \
    git \
    gnupg2 \
    graphviz \
    graphviz-dev \
    libgomp1 \
    libpng-dev \
    openjdk-11-jdk \
    squashfs-tools \
    tree \
    unzip \
    wget \
    zlib1g-dev \
    && wget https://imagemagick.org/archive/binaries/magick -O /usr/bin/magick \
    && chmod a+x /usr/bin/magick

# Stage: ANTs
FROM requirements as ants
ARG ANTS_VER=2.3.1
RUN curl -fsSL --retry 5 https://dl.dropbox.com/s/1xfhydsf4t4qoxg/ants-Linux-centos6_x86_64-v${ANTS_VER}.tar.gz -o /tmp/ants.tar.gz \
    && mkdir -p /opt/ants/bin \
    && tar -xzf /tmp/ants.tar.gz -C /opt/ants/bin --strip-components 1

# Stage: Itksnap
FROM requirements as itksnap
RUN wget https://sourceforge.net/projects/itk-snap/files/itk-snap/Nightly/itksnap-nightly-master-Linux-gcc64-qt4.tar.gz/download -O /tmp/itksnap.tar.gz \
    && tar -xzf /tmp/itksnap.tar.gz -C /opt \
    && mv /opt/itksnap-*/ /opt/itksnap 

# Stage: Niftyreg
FROM requirements as niftyreg
ARG NIFTYREG_VER=1.3.9
RUN wget https://sourceforge.net/projects/niftyreg/files/nifty_reg-${NIFTYREG_VER}/NiftyReg-${NIFTYREG_VER}-Linux-x86_64-Release.tar.gz/download -O /tmp/niftyreg-${NIFTYREG_VER}.tar.gz \
    && tar -xzf /tmp/niftyreg-${NIFTYREG_VER}.tar.gz -C /opt \
    && mv /opt/NiftyReg-${NIFTYREG_VER}-Linux-x86_64-Release /opt/niftyreg

# Stage: Nighres
FROM requirements as nighres 
ARG JCC_VER=3.10
ARG NIGHRES_COMMIT=1901ce9a9afdfad8e2d66ec09600fbfb9fa0151d
RUN wget https://files.pythonhosted.org/packages/97/c6/9249f9cc99404e782ce06b3a3710112c32783df59e9bd5ef94cd2771ccaa/JCC-${JCC_VER}.tar.gz -O /tmp/JCC-${JCC_VER}.tar.gz \
    && tar -xzf /tmp/JCC-${JCC_VER}.tar.gz -C /tmp
COPY ./nighres_custom/setup.py /tmp/JCC-${JCC_VER}
WORKDIR /tmp/JCC-${JCC_VER}
RUN export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-$(dpkg --print-architecture) \
    && export JCC_JDK=$JAVA_HOME \
    && export LD_LIBRARY_PATH=$JAVA_HOME/lib:${LD_LIBRARY_PATH} \
    && export PATH=$JAVA_HOME/bin:${PATH} \
    && python setup.py install
WORKDIR /tmp 
RUN git clone https://github.com/nighres/nighres \
    && cd nighres \
    && git checkout ${NIGHRES_COMMIT} \
    && ./build.sh \
    && pip install --no-cache-dir . \
    && rm -rf /tmp/JCC-* /tmp/nighres
WORKDIR / 

# Stage: Workbench
FROM requirements as workbench
ARG WB_VER=1.5.0
RUN wget -q https://www.humanconnectome.org/storage/app/media/workbench/workbench-linux64-v${WB_VER}.zip -O /tmp/workbench.zip \
    && unzip -qq /tmp/workbench.zip -d /opt 

# Stage: hippunfold_deps
# Note: A minified version of ANTs is installed to save space. 
FROM nighres as hippunfold_deps
LABEL author alik@robarts.ca
COPY --from=ants \
    # Commands to copy
    /opt/ants/bin/antsRegistration \
    /opt/ants/bin/antsApplyTransforms \
    /opt/ants/bin/N4BiasFieldCorrection \
    /opt/ants/bin/ComposeMultiTransform \
    /opt/ants/bin/antsRegistrationSyNQuick.sh \
    /opt/ants/bin/PrintHeader \
    # Target destination
    /opt/ants-minify/bin/
COPY --from=itksnap /opt/itksnap /opt/itksnap
COPY --from=niftyreg /opt/niftyreg /opt/niftyreg
COPY --from=workbench /opt/workbench /opt/workbench
COPY . /tmp/src/
WORKDIR /tmp/src
ENV OS=Linux \
    _JAVA_OPTIONS= \
    ANTSPATH=/opt/ants-minify/bin \
    LD_LIBRARY_PATH=/opt/itksnap/lib:/opt/niftyreg/lib:/opt/workbench/libs_linux64:/opt/workbench/libs_linux64_software_opengl:${LD_LIBRARY_PATH} \
    PATH=/opt/ants-minify:/opt/ants-minify/bin:/opt/itksnap/bin:/opt/niftyreg/bin:/opt/workbench/bin_linux64:${PATH} \
    SKLEARN_ALLOW_DEPRECATED_SKLEARN_PACKAGE_INSTALL=True
RUN pip install --no-cache-dir . \
    && cd / \
    && rm -rf /tmp/src \
    && apt-get purge -y -q curl unzip wget \
    && apt-get --purge -y -qq autoremove
WORKDIR /
ENTRYPOINT ["/bin/bash"]
