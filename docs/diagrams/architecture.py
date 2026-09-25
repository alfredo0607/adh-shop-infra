"""
Renders docs/architecture.png, the AWS architecture diagram in the README.

Regenerate after changing the infrastructure, from the repository root:

    docker run --rm -v "$PWD/docs:/docs" -w /docs/diagrams python:3.12-slim sh -c \
      "apt-get update -qq && apt-get install -y -qq graphviz >/dev/null && \
       pip install -q diagrams==0.24.4 && python architecture.py"
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2, ECR
from diagrams.aws.database import Dynamodb, ElasticacheForRedis
from diagrams.aws.management import Cloudwatch, SystemsManagerParameterStore
from diagrams.aws.network import CloudFront, Endpoint, InternetGateway
from diagrams.aws.security import IAMRole, KMS
from diagrams.aws.storage import S3
from diagrams.generic.place import Datacenter
from diagrams.onprem.ci import GithubActions
from diagrams.onprem.client import Users
from diagrams.onprem.network import Nginx
from diagrams.programming.language import Nodejs
from diagrams.saas.cdn import Cloudflare

GRAPH = {
    "pad": "0.5",
    "nodesep": "0.7",
    "ranksep": "0.9",
    "splines": "spline",
    "fontsize": "22",
    "fontname": "Helvetica",
    "labelloc": "t",
}
CLUSTER_EXTERNAL = {"bgcolor": "#F7F7F7", "pencolor": "#AAAAAA", "fontsize": "14"}
CLUSTER_AWS = {"bgcolor": "#FFF8EE", "pencolor": "#FF9900", "penwidth": "2", "fontsize": "16"}
CLUSTER_VPC = {"bgcolor": "#F2FBF2", "pencolor": "#248814", "penwidth": "2", "fontsize": "14"}
CLUSTER_PUBLIC = {"bgcolor": "#E9F7E9", "pencolor": "#7AA116", "style": "dashed", "fontsize": "13"}
CLUSTER_PRIVATE = {"bgcolor": "#E8F1FB", "pencolor": "#147EBA", "style": "dashed", "fontsize": "13"}
CLUSTER_HOST = {"bgcolor": "#FFFFFF", "pencolor": "#D86613", "fontsize": "13"}
CLUSTER_PLAIN = {"bgcolor": "#FFFFFF", "pencolor": "#AAAAAA", "fontsize": "13"}

TRAFFIC = {"color": "#1F2937", "penwidth": "2"}
DATA = {"color": "#147EBA", "penwidth": "1.6"}
DEPLOY = {"color": "#8C4FFF", "penwidth": "1.4", "style": "dashed"}
PAYMENT = {"color": "#B91C1C", "penwidth": "1.6"}
QUIET = {"color": "#888888", "style": "dotted"}

with Diagram(
    "ADH Shop — AWS architecture (us-east-1)",
    filename="../architecture",
    outformat="png",
    direction="TB",
    show=False,
    graph_attr=GRAPH,
):
    with Cluster("Outside AWS", graph_attr=CLUSTER_EXTERNAL):
        customer = Users("Customers\nbrowser / phone")
        cloudflare = Cloudflare("Cloudflare\nTLS · DDoS · WAF")
        gateway = Datacenter("Payment gateway\n(sandbox)")
        github = GithubActions("GitHub Actions\nCI / CD")

    with Cluster("AWS · us-east-1", graph_attr=CLUSTER_AWS):
        with Cluster("VPC 10.20.0.0/16 · 2 AZs · no NAT gateway", graph_attr=CLUSTER_VPC):
            igw = InternetGateway("Internet gateway")

            with Cluster(
                "Public subnets 10.20.1.0/24 · 10.20.2.0/24\n"
                "Security group: 443 from Cloudflare ranges only",
                graph_attr=CLUSTER_PUBLIC,
            ):
                with Cluster("EC2 t3.micro · Elastic IP · IMDSv2", graph_attr=CLUSTER_HOST):
                    host = EC2("Container host")
                    nginx = Nginx("nginx :443\nblue/green upstream")
                    api = Nodejs("NestJS API\n127.0.0.1:3000 | 3001")

            with Cluster(
                "Private subnets 10.20.11.0/24 · 10.20.12.0/24\nno route to the internet",
                graph_attr=CLUSTER_PRIVATE,
            ):
                cache = ElasticacheForRedis("Valkey 8 Serverless\nIAM auth · TLS")

            ddb_endpoint = Endpoint("Gateway endpoint\nDynamoDB")
            s3_endpoint = Endpoint("Gateway endpoint\nS3")

        dynamodb = Dynamodb("DynamoDB\nadh-shop-store\nsingle table · GSI1 · TTL")

        with Cluster("Private image delivery", graph_attr=CLUSTER_PLAIN):
            cdn = CloudFront("CloudFront\nsigned URLs only")
            assets = S3("Assets bucket\nprivate · OAC")
            kms = KMS("KMS key")

        with Cluster("Operations", graph_attr=CLUSTER_PLAIN):
            ecr = ECR("ECR\nimmutable · scanned")
            params = SystemsManagerParameterStore("Parameter Store\n/adh-shop/*")
            scripts = S3("Scripts bucket")
            logs = Cloudwatch("CloudWatch\nnginx · flow logs")
            roles = IAMRole("IAM\nhost role · OIDC role")

    # Runtime traffic
    customer >> Edge(label="HTTPS", **TRAFFIC) >> cloudflare
    cloudflare >> Edge(label="HTTPS · Cloudflare IPs only", **TRAFFIC) >> igw
    igw >> Edge(**TRAFFIC) >> nginx
    nginx >> Edge(label="loopback", **TRAFFIC) >> api

    # Data
    api >> Edge(label="rate-limit counters", **DATA) >> cache
    api >> Edge(**DATA) >> ddb_endpoint >> Edge(**DATA) >> dynamodb
    customer >> Edge(label="signed image URL", **DATA) >> cdn
    cdn >> Edge(label="Origin Access Control", **DATA) >> assets
    assets >> Edge(label="SSE-KMS", **QUIET) >> kms

    # Payments
    api >> Edge(label="charge · status", **PAYMENT) >> gateway
    gateway >> Edge(label="signed events", **PAYMENT) >> cloudflare

    # Deployment and operations
    github >> Edge(label="OIDC · push image", **DEPLOY) >> ecr
    github >> Edge(label="SSM SendCommand", **DEPLOY) >> host
    host >> Edge(label="pull image", **DEPLOY) >> ecr
    host >> Edge(label="config at deploy", **DEPLOY) >> params
    host >> Edge(**DEPLOY) >> s3_endpoint >> Edge(**DEPLOY) >> scripts
    host >> Edge(label="logs", **DEPLOY) >> logs
    host >> Edge(label="instance role", **QUIET) >> roles
