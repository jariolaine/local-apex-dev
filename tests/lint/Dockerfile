FROM rhysd/actionlint:latest

USER root

RUN apk add --no-cache \
      bash \
      git \
      nodejs \
      npm \
      py3-pip \
      py3-virtualenv \
    && python3 -m venv /opt/python-tools \
    && /opt/python-tools/bin/pip install \
      --no-cache-dir \
      yamllint \
      sqlfluff \
    && ln -s /opt/python-tools/bin/yamllint /usr/local/bin/yamllint \
    && ln -s /opt/python-tools/bin/sqlfluff /usr/local/bin/sqlfluff \
    && npm install --global \
      markdownlint-cli2@latest \
    && git config --system --add safe.directory /repo

ENV PATH="/opt/python-tools/bin:${PATH}"

WORKDIR /repo

ENTRYPOINT ["/bin/bash"]
