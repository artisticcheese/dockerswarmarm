[Environment]::SetEnvironmentVariable("DOCKER_CERT_PATH", "certs/", "Process")

docker -H iyhcpbbqzm4jy.southcentralus.cloudapp.azure.com:2376 --tls ps 