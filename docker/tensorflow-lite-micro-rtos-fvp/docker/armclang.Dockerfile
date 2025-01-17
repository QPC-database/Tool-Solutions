#----------------------------------------------------------------------------
# Step 1. Install newer CMake, 3.15.6 or newer is required to build the Ethos-U55 driver
#----------------------------------------------------------------------------
FROM multiarch/ubuntu-core:amd64-bionic as cmake_install
RUN apt-get -y update \
  && apt-get -y install wget \
  && rm -rf /var/lib/apt/lists/* \
  && wget https://github.com/Kitware/CMake/releases/download/v3.20.1/cmake-3.20.1-Linux-x86_64.sh \
  && mkdir -p /usr/local/cmake \
  && bash cmake-3.20.1-Linux-x86_64.sh --skip-license --exclude-subdir --prefix=/usr/local/cmake \
  && rm cmake-3.20.1-Linux-x86_64.sh

#----------------------------------------------------------------------------
# Step 1: Install Arm Compiler 6
#----------------------------------------------------------------------------
FROM multiarch/ubuntu-core:amd64-bionic as armclang_install
ADD downloads/DS500-BN-00026-r5p0-18rel0.tgz /tmp/AC6
RUN /tmp/AC6/install_x86_64.sh --i-agree-to-the-contained-eula --no-interactive -d /usr/local/AC6 \
  && rm -rf /tmp/AC6

#----------------------------------------------------------------------------
# Step 2: Install Arm Corstone-300 FVP with Ethos-U55 into system directory 
#----------------------------------------------------------------------------
FROM multiarch/ubuntu-core:amd64-bionic as fvp_install
ADD downloads/FVP_Corstone_SSE-300_Ethos-U55_11.14_24.tgz /tmp/FVP
RUN /tmp/FVP/FVP_Corstone_SSE-300_Ethos-U55.sh --i-agree-to-the-contained-eula -d /usr/local/FVP_Corstone_SSE-300_Ethos-U55 --no-interactive \
  && rm -rf /tmp/FVP

#----------------------------------------------------------------------------
# Step 3: Install vela
#----------------------------------------------------------------------------
FROM multiarch/ubuntu-core:amd64-bionic as vela_install
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/usr/local/.vela/bin:$PATH
COPY requirements.txt requirements.txt

RUN apt-get -y update \
  && apt-get -y install python3 python3-venv python3-dev python3-pip \
  && rm -rf /var/lib/apt/lists/* \
  && python3 -m venv /usr/local/.vela \
  && pip install --upgrade pip setuptools \
  && pip install -r requirements.txt

#----------------------------------------------------------------------------
# Step 4: Install dependenices to the armclang image
#----------------------------------------------------------------------------
FROM multiarch/ubuntu-core:amd64-bionic as armclang_main

SHELL ["/bin/bash", "-c"]
LABEL maintainer="tobias.andersson@arm.com"

RUN echo "root:docker" | chpasswd

RUN apt-get -y update \
  && apt-get -y install \
  	sudo nano git git-lfs vim wget \
  	make telnet curl zip xterm \
  	bc build-essential libsndfile1 \
  	software-properties-common gosu \
  && DEBIAN_FRONTEND=noninteractive apt-get -y install python3 python3-venv python3-tk \
  && rm -rf /var/lib/apt/lists/*

#---------------------------------------------------------------------------
# COPY entrypoint script
#---------------------------------------------------------------------------
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN sed -i 's/\r//' /usr/local/bin/entrypoint.sh \
  && chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

#---------------------------------------------------------------------------
# COPY over cmake from cmake image
#---------------------------------------------------------------------------
COPY --from=cmake_install /usr/local/cmake /usr/local/cmake

#---------------------------------------------------------------------------
# COPY over cmake from vela install image
#---------------------------------------------------------------------------
COPY --from=vela_install /usr/local/.vela /usr/local/.vela

#----------------------------------------------------------------------------
# Copy ArmClang installation from armclang install image
#----------------------------------------------------------------------------
COPY --from=armclang_install /usr/local/AC6 /usr/local/AC6

#----------------------------------------------------------------------------
# Copy FVP installation from fvp install image
#----------------------------------------------------------------------------
COPY --from=fvp_install /usr/local/FVP_Corstone_SSE-300_Ethos-U55 /usr/local/FVP_Corstone_SSE-300_Ethos-U55

#----------------------------------------------------------------------------
# Setup Environment Variables
#----------------------------------------------------------------------------
ENV PATH="/usr/local/.vela/bin:/usr/local/AC6/bin:/usr/local/cmake/bin:/usr/local/FVP_Corstone_SSE-300_Ethos-U55/models/Linux64_GCC-6.4:${PATH}"
ENV COMPILER="armclang"

#----------------------------------------------------------------------------
# Add path to helper scripts 
#----------------------------------------------------------------------------
ADD scripts/convert_scripts /usr/local/convert_scripts
ENV PATH=/usr/local/convert_scripts:$PATH
RUN sed -i 's/\r//' /usr/local/convert_scripts/*.sh \
  && chmod +x /usr/local/convert_scripts/*.sh

#----------------------------------------------------------------------------
# Workdir
#----------------------------------------------------------------------------
RUN mkdir -p -m777 /work
WORKDIR /work

#----------------------------------------------------------------------------
# copy sw
#----------------------------------------------------------------------------
COPY sw /work/sw
RUN sed -i 's/\r//' sw/data_injection_utils/*.py

#----------------------------------------------------------------------------
# Add build Script
#----------------------------------------------------------------------------
COPY linux_build_rtos_apps.sh .
RUN  sed -i 's/\r//' linux_build_rtos_apps.sh \
  && chmod +x linux_build_rtos_apps.sh

COPY download_use_case_model.sh .
RUN  sed -i 's/\r//' download_use_case_model.sh \
  && chmod +x download_use_case_model.sh

COPY linux_build_eval_kit_apps.sh .
RUN  sed -i 's/\r//' linux_build_eval_kit_apps.sh \
  && chmod +x linux_build_eval_kit_apps.sh

#----------------------------------------------------------------------------
# Add run script
#----------------------------------------------------------------------------
COPY data_injection_demo.py .
RUN sed -i 's/\r//' data_injection_demo.py \
  && chmod +x data_injection_demo.py
  
COPY run_demo_app.sh .
RUN sed -i 's/\r//' run_demo_app.sh \
  && chmod +x run_demo_app.sh

COPY docker/bashrc /etc/bash.bashrc
RUN  sed -i 's/\r//' /etc/bash.bashrc

CMD ["/bin/bash"]
