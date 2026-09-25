"""
Builds docs/diagrams/architecture.drawio, the AWS architecture diagram, using the
official AWS 2024 shape library that ships with diagrams.net (draw.io).

The .drawio file is the source of truth for the picture: open it in diagrams.net
to edit by hand. This script exists so the layout stays on a grid and can be
regenerated after an infrastructure change:

    python docs/diagrams/build_architecture.py
    docker run --rm -v "$PWD/docs/diagrams:/data" rlespinasse/drawio-export \
      --format png --scale 2 --border 20 --output export
"""

from __future__ import annotations

import html
from pathlib import Path
from xml.sax.saxutils import quoteattr

OUT = Path(__file__).with_name("architecture.drawio")

# AWS 2024 category colours, as used by the official icon set.
COMPUTE = "#ED7100"
DATABASE = "#C925D1"
NETWORK = "#8C4FFF"
STORAGE = "#7AA116"
SECURITY = "#DD344C"
MANAGEMENT = "#E7157B"
INK = "#232F3E"
MUTED = "#545B64"

REQUEST = INK
DATA = "#147EBA"
PAYMENT = "#DD344C"
DEPLOY = NETWORK

cells: list[str] = []
_next = [2]


def _id() -> str:
    _next[0] += 1
    return f"c{_next[0]}"


def _cell(value: str, style: str, x: float, y: float, w: float, h: float, *, vertex=True) -> str:
    cid = _id()
    kind = 'vertex="1"' if vertex else 'edge="1"'
    cells.append(
        f'<mxCell id="{cid}" value={quoteattr(value)} style={quoteattr(style)} {kind} parent="1">'
        f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>'
    )
    return cid


def group(label: str, x, y, w, h, kind: str) -> str:
    base = (
        "points=[];outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;fontSize=13;"
        "container=0;pointerEvents=0;collapsible=0;recursiveResize=0;verticalAlign=top;"
        "align=left;spacingLeft=30;spacingTop=2;"
    )
    styles = {
        "cloud": base + "shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_aws_cloud_alt;"
        f"strokeColor={INK};fillColor=none;fontColor={INK};fontStyle=1;dashed=0;",
        "region": base + "shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_region;"
        "strokeColor=#00A4A6;fillColor=none;fontColor=#147EBA;dashed=1;fontStyle=1;",
        "vpc": base + "shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_vpc2;"
        f"strokeColor={NETWORK};fillColor=none;fontColor={NETWORK};dashed=0;fontStyle=1;",
        "public": base + "shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_security_group;"
        "grStroke=0;strokeColor=#7AA116;fillColor=#F2F6E8;fontColor=#248814;dashed=0;",
        "private": base + "shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_security_group;"
        "grStroke=0;strokeColor=#00A4A6;fillColor=#E6F6F7;fontColor=#147EBA;dashed=0;",
        "ec2": base + "shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_ec2_instance_contents;"
        f"strokeColor={COMPUTE};fillColor=#FFFFFF;fontColor={COMPUTE};dashed=0;",
        "az": "fillColor=none;strokeColor=#147EBA;dashed=1;verticalAlign=top;fontStyle=0;"
        "fontColor=#147EBA;whiteSpace=wrap;html=1;fontSize=12;",
        "sg": "fillColor=none;strokeColor=#DD3522;dashed=1;dashPattern=6 4;verticalAlign=bottom;"
        "align=right;spacingRight=8;spacingBottom=4;fontStyle=0;fontColor=#DD3522;"
        "whiteSpace=wrap;html=1;fontSize=11;rounded=0;",
        "plain": "fillColor=#FAFAFA;strokeColor=#AAB7B8;dashed=1;verticalAlign=top;align=left;"
        f"spacingLeft=10;spacingTop=4;fontStyle=1;fontColor={MUTED};whiteSpace=wrap;html=1;"
        "fontSize=12;rounded=1;arcSize=2;",
    }
    return _cell(label, styles[kind], x, y, w, h)


def service(label: str, x, y, icon: str, fill: str, size=56) -> str:
    """A service in the official style: coloured square, white glyph, label below."""
    style = (
        f"sketch=0;outlineConnect=0;fontColor={INK};gradientColor=none;fillColor={fill};"
        "strokeColor=#ffffff;dashed=0;verticalLabelPosition=bottom;verticalAlign=top;"
        "align=center;html=1;fontSize=11;fontStyle=0;aspect=fixed;whiteSpace=wrap;"
        "labelWidth=170;"
        f"shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.{icon};"
    )
    return _cell(label, style, x, y, size, size)


def resource(label: str, x, y, shape: str, fill: str, size=44, label_right=False) -> str:
    """A resource glyph (no background square), as used inside VPC diagrams."""
    position = (
        "labelPosition=right;verticalLabelPosition=middle;align=left;verticalAlign=middle;"
        "spacingLeft=6;"
        if label_right
        else "verticalLabelPosition=bottom;verticalAlign=top;align=center;labelWidth=130;"
    )
    style = (
        f"sketch=0;outlineConnect=0;fontColor={INK};gradientColor=none;fillColor={fill};"
        f"strokeColor=none;dashed=0;{position}"
        "html=1;fontSize=11;fontStyle=0;aspect=fixed;pointerEvents=1;"
        f"whiteSpace=wrap;shape=mxgraph.aws4.{shape};"
    )
    return _cell(label, style, x, y, size, size)


def box(label: str, x, y, w, h, *, fill="#FFFFFF", stroke=INK, font=INK, bold=False,
        dashed=False, size=11, rounded=True) -> str:
    style = (
        f"rounded={1 if rounded else 0};arcSize=10;whiteSpace=wrap;html=1;fillColor={fill};"
        f"strokeColor={stroke};fontColor={font};fontSize={size};"
        f"fontStyle={1 if bold else 0};dashed={1 if dashed else 0};strokeWidth=1.5;"
    )
    return _cell(label, style, x, y, w, h)


def text(label: str, x, y, w, h, *, size=12, color=INK, bold=False, align="left") -> str:
    style = (
        f"text;html=1;strokeColor=none;fillColor=none;align={align};verticalAlign=middle;"
        f"whiteSpace=wrap;fontSize={size};fontColor={color};fontStyle={1 if bold else 0};"
    )
    return _cell(label, style, x, y, w, h)


def badge(label: str, x, y, colour: str) -> str:
    style = (
        f"ellipse;whiteSpace=wrap;html=1;aspect=fixed;fillColor={colour};strokeColor=#FFFFFF;"
        "strokeWidth=2;fontColor=#FFFFFF;fontStyle=1;fontSize=12;"
    )
    return _cell(label, style, x, y, 26, 26)


def edge(src: str, dst: str, colour: str, *, dashed=False, label="", points=(),
         exit=None, entry=None, both=False, width=2.0) -> str:
    style = (
        "edgeStyle=orthogonalEdgeStyle;rounded=1;orthogonalLoop=1;jettySize=auto;html=1;"
        f"strokeColor={colour};strokeWidth={width};fontSize=10;fontColor={colour};"
        "labelBackgroundColor=#FFFFFF;endArrow=block;endFill=1;"
        f"{'startArrow=block;startFill=1;' if both else ''}"
        f"{'dashed=1;dashPattern=8 5;' if dashed else ''}"
    )
    if exit:
        style += f"exitX={exit[0]};exitY={exit[1]};exitDx=0;exitDy=0;"
    if entry:
        style += f"entryX={entry[0]};entryY={entry[1]};entryDx=0;entryDy=0;"
    cid = _id()
    pts = "".join(f'<mxPoint x="{px}" y="{py}"/>' for px, py in points)
    geometry = (
        f'<mxGeometry relative="1" as="geometry">'
        f'{f"<Array as=\"points\">{pts}</Array>" if pts else ""}</mxGeometry>'
    )
    cells.append(
        f'<mxCell id="{cid}" value={quoteattr(label)} style={quoteattr(style)} edge="1" '
        f'parent="1" source="{src}" target="{dst}">{geometry}</mxCell>'
    )
    return cid


# ── Title ────────────────────────────────────────────────────────────────────
text("ADH Shop — production architecture on AWS", 40, 18, 900, 34, size=24, bold=True)
text(
    "Checkout API for a card-paid storefront · us-east-1 · single-table DynamoDB · "
    "blue/green on EC2 behind Cloudflare · deployed from GitHub through OIDC",
    40, 52, 1300, 22, size=13, color=MUTED,
)

# ── Outside AWS ──────────────────────────────────────────────────────────────
group("Outside AWS", 30, 100, 250, 1230, "plain")
users = resource("<b>Customers</b><br>browser · mobile", 60, 250, "users", INK, 56, label_right=True)
cloudflare = _cell(
    "<b>Cloudflare</b><br><font style='font-size:10px'>proxied DNS · TLS<br>WAF · DDoS</font>",
    "shape=cloud;whiteSpace=wrap;html=1;fillColor=#F38020;strokeColor=none;"
    "fontColor=#FFFFFF;fontSize=13;",
    55, 520, 200, 120,
)
gateway = box(
    "<b>Payment gateway</b><br>sandbox<br><font color='#545B64'>charges · status · events</font>",
    60, 860, 190, 86, fill="#FDEDEF", stroke=PAYMENT,
)
github = box(
    "<b>GitHub Actions</b><br><font color='#D1D5DA'>CI on every PR · CD on merge</font>",
    60, 1160, 190, 70, fill="#24292F", stroke="#24292F", font="#FFFFFF",
)

# ── AWS Cloud, global edge ───────────────────────────────────────────────────
group("AWS Cloud", 310, 100, 1580, 1230, "cloud")
group("Global · edge locations", 330, 140, 330, 150, "plain")
cloudfront = service(
    "<b>Amazon CloudFront</b><br>signed URLs only · OAC", 360, 180, "cloudfront", NETWORK
)
text(
    "Key group rejects unsigned<br>or tampered requests at the<br>edge (403).",
    480, 170, 170, 60, size=10, color=MUTED,
)

# ── Region and VPC ───────────────────────────────────────────────────────────
group("US East (N. Virginia) · us-east-1", 330, 310, 1540, 1000, "region")
group("VPC · 10.20.0.0/16 · no NAT gateway", 355, 355, 935, 930, "vpc")

igw = resource("Internet<br>gateway", 333, 562, "internet_gateway", NETWORK, 44)

group("Availability Zone · us-east-1a", 385, 400, 435, 865, "az")
group("Availability Zone · us-east-1b", 835, 400, 435, 865, "az")

group("Public subnet · 10.20.1.0/24", 405, 440, 395, 500, "public")
group("Public subnet · 10.20.2.0/24", 855, 440, 395, 500, "public")
group("Private subnet · 10.20.11.0/24 · no route to the internet", 405, 965, 395, 280, "private")
group("Private subnet · 10.20.12.0/24 · no route to the internet", 855, 965, 395, 280, "private")

group("Security group · 443 from Cloudflare IP ranges only", 420, 480, 365, 445, "sg")
group("EC2 · t3.micro · IMDSv2 · Elastic IP", 435, 515, 335, 370, "ec2")
host = resource("", 718, 522, "instance2", COMPUTE, 36)

nginx = box(
    "<b>nginx :443</b> · TLS to origin · blue/green upstream", 455, 568, 295, 46,
    stroke=COMPUTE,
)
api_blue = box(
    "<b>API · blue</b><br>NestJS container<br>127.0.0.1:3000 · <i>serving</i>",
    455, 668, 140, 76, fill="#EAF3FB", stroke=DATA,
)
api_green = box(
    "<b>API · green</b><br>next release<br>127.0.0.1:3001 · <i>idle</i>",
    610, 668, 140, 76, fill="#FFFFFF", stroke=DATA, dashed=True,
)
text(
    "Reservation expiry job in-process, every 60 s<br>Structured JSON logs · request id per call",
    455, 770, 295, 40, size=10, color=MUTED,
)
text(
    "Reserved for a second host<br>(ALB + Auto Scaling path to multi-AZ)",
    875, 840, 355, 60, size=11, color="#6B8E23", align="center",
)

cache = service(
    "<b>ElastiCache Serverless</b><br>Valkey 8 · rate-limit counters<br>"
    "IAM auth · TLS · 1 GB / 5k ECPU cap",
    574, 1040, "elasticache", DATABASE,
)
cache_b = service("cache endpoint (ENI)", 1024, 1040, "elasticache", DATABASE, 48)

ddb_endpoint = resource("Gateway endpoint<br>DynamoDB", 1268, 596, "endpoints", NETWORK, 44)
s3_endpoint = resource("Gateway endpoint<br>S3", 1268, 800, "endpoints", NETWORK, 44)

# ── Regional services ────────────────────────────────────────────────────────
group("Data", 1340, 355, 510, 330, "plain")
dynamodb = service(
    "<b>Amazon DynamoDB</b><br>adh-shop-store · on-demand<br>single table · GSI1 · TTL",
    1380, 420, "dynamodb", DATABASE,
)
assets = service(
    "<b>Amazon S3 · assets</b><br>private · versioned", 1575, 420, "s3", STORAGE
)
kms = service("<b>AWS KMS</b><br>assets key", 1760, 420, "key_management_service", SECURITY)
text(
    "Products · customers · transactions ·<br>deliveries · idempotency keys",
    1360, 625, 460, 40, size=10, color=MUTED,
)

ops = group("Delivery and operations", 1340, 715, 510, 570, "plain")
ecr = service("<b>Amazon ECR</b><br>immutable tags<br>scan on push", 1380, 775, "ecr", COMPUTE)
params = service(
    "<b>SSM Parameter Store</b><br>/adh-shop/* · SecureString",
    1575, 775, "systems_manager", MANAGEMENT,
)
runcmd = service(
    "<b>SSM Run Command</b><br>deploy.sh on the host", 1760, 775, "systems_manager", MANAGEMENT
)
scripts = service("<b>Amazon S3 · scripts</b><br>deploy.sh · add-api.sh", 1380, 990, "s3", STORAGE)
cloudwatch = service(
    "<b>Amazon CloudWatch</b><br>nginx logs · VPC flow<br>logs (rejects, 30 d)",
    1575, 990, "cloudwatch_2", MANAGEMENT,
)
iam = service(
    "<b>AWS IAM</b><br>host role · GitHub OIDC<br>deploy role",
    1760, 990, "identity_and_access_management", SECURITY,
)

# ── Flows ────────────────────────────────────────────────────────────────────
edge(users, cloudflare, REQUEST, exit=(0.5, 1), entry=(0.35, 0.08))
badge("1", 75, 400, REQUEST)

edge(cloudflare, igw, REQUEST, exit=(0.95, 0.5), entry=(0, 0.5))
badge("2", 283, 555, REQUEST)
edge(igw, nginx, REQUEST, exit=(1, 0.5), entry=(0, 0.5), points=[(420, 584), (420, 591)])

edge(nginx, api_blue, REQUEST, exit=(0.18, 1), entry=(0.5, 0))
badge("3", 530, 628, REQUEST)
edge(nginx, api_green, REQUEST, dashed=True, exit=(0.72, 1), entry=(0.5, 0), width=1.2)

edge(api_blue, cache, DATA, exit=(0.5, 1), entry=(0.5, 0), points=[(525, 1000), (602, 1000)])
badge("4", 485, 990, DATA)

edge(api_blue, ddb_endpoint, DATA, exit=(1, 0.3), entry=(0, 0.5), points=[(605, 691), (605, 618)])
edge(ddb_endpoint, dynamodb, DATA, exit=(1, 0.5), entry=(0, 0.5),
     points=[(1318, 618), (1318, 448)])
badge("5", 1180, 604, DATA)

edge(api_blue, gateway, PAYMENT, exit=(0, 0.75), entry=(1, 0.5),
     points=[(445, 725), (445, 903)])
badge("6", 300, 890, PAYMENT)
edge(gateway, cloudflare, PAYMENT, exit=(0.5, 0), entry=(0.5, 0.9))
badge("7", 142, 760, PAYMENT)

edge(users, cloudfront, DATA, exit=(0.5, 0), entry=(0, 0.5), points=[(88, 208)])
badge("8", 200, 195, DATA)
edge(cloudfront, assets, DATA, exit=(0.5, 1), entry=(0.5, 0),
     points=[(388, 300), (1603, 300)])
edge(assets, kms, MUTED, dashed=True, exit=(1, 0.5), entry=(0, 0.5), width=1.2)

edge(github, ops, DEPLOY, dashed=True, exit=(1, 0.5), entry=(0.5, 1),
     points=[(300, 1195), (300, 1300), (1595, 1300)])
badge("A", 900, 1287, DEPLOY)
badge("B", 940, 1287, DEPLOY)
edge(runcmd, host, DEPLOY, dashed=True, both=True, exit=(0.5, 0), entry=(1, 0.25),
     points=[(1788, 700), (826, 700), (826, 531)])
badge("C", 1100, 687, DEPLOY)
badge("D", 799, 745, DEPLOY)
edge(host, s3_endpoint, DEPLOY, dashed=True, exit=(1, 0.8), entry=(0, 0.5),
     points=[(812, 551), (812, 822)], width=1.4)
edge(s3_endpoint, scripts, DEPLOY, dashed=True, exit=(1, 0.5), entry=(0, 0.5),
     points=[(1326, 822), (1326, 1018)], width=1.4)

# ── Legend ───────────────────────────────────────────────────────────────────
group("How it works", 1915, 100, 390, 1230, "plain")
steps = [
    ("1", REQUEST, "Customers reach the API through <b>Cloudflare</b>: proxied DNS, TLS, WAF and DDoS protection."),
    ("2", REQUEST, "The host accepts <b>443 only from Cloudflare's IP ranges</b>, so nobody can reach it around the edge or forge the client address."),
    ("3", REQUEST, "<b>nginx</b> proxies over loopback to the active colour. The idle colour receives the next release."),
    ("4", DATA, "Rate-limit counters in <b>Valkey</b>: IAM token auth, TLS, subnets with no internet route."),
    ("5", DATA, "<b>DynamoDB</b> through a gateway endpoint: conditional writes stop overselling; each settlement is one TransactWriteItems."),
    ("6", PAYMENT, "The API charges a <b>card token</b> (card data never reaches AWS), signed with the integrity secret, and polls the outcome."),
    ("7", PAYMENT, "The gateway pushes <b>signed events</b> back through Cloudflare to the webhook."),
    ("8", DATA, "Product images: browser → <b>CloudFront</b> with a signed, expiring URL → private S3 through Origin Access Control, KMS-encrypted."),
]
deploy_steps = [
    ("A", "GitHub Actions assumes an <b>IAM role through OIDC</b>. No AWS keys are stored in GitHub."),
    ("B", "It pushes the image to <b>ECR</b>, tagged with the commit SHA. Tags are immutable."),
    ("C", "<b>SSM Run Command</b> runs deploy.sh on the host. No SSH, no open admin port needed."),
    ("D", "The host pulls the image, reads /adh-shop/* from <b>Parameter Store</b>, starts the idle colour and switches only when <b>/ready</b> reads DynamoDB."),
]

y = 140
text("<b>Checkout request path</b>", 1935, y, 350, 22, size=13)
y += 30
for label, colour, body in steps:
    badge(label, 1935, y, colour)
    text(body, 1970, y - 6, 320, 64, size=11)
    y += 74
y += 10
text("<b>Deployment</b>", 1935, y, 350, 22, size=13)
y += 30
for label, body in deploy_steps:
    badge(label, 1935, y, DEPLOY)
    text(body, 1970, y - 6, 320, 64, size=11)
    y += 74

y += 6
text("<b>Lines</b>", 1935, y, 350, 22, size=13)
y += 28
for colour, dashed, meaning in [
    (REQUEST, False, "Customer traffic"),
    (DATA, False, "Data and images"),
    (PAYMENT, False, "Payment gateway"),
    (DEPLOY, True, "Deployment and operations"),
]:
    a = _cell("", "text;strokeColor=none;fillColor=none;", 1935, y + 8, 1, 1)
    b = _cell("", "text;strokeColor=none;fillColor=none;", 1995, y + 8, 1, 1)
    edge(a, b, colour, dashed=dashed)
    text(meaning, 2005, y - 2, 280, 20, size=11)
    y += 26

text(
    "Source: docs/diagrams/architecture.drawio · open and edit in diagrams.net",
    40, 1340, 900, 20, size=10, color=MUTED,
)

# ── Write ────────────────────────────────────────────────────────────────────
xml = (
    '<mxfile host="build_architecture.py" type="device">'
    '<diagram id="architecture" name="AWS architecture">'
    '<mxGraphModel dx="2400" dy="1400" grid="1" gridSize="10" guides="1" tooltips="1" '
    'connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="2340" '
    'pageHeight="1380" background="#FFFFFF" math="0" shadow="0"><root>'
    '<mxCell id="0"/><mxCell id="1" parent="0"/>'
    + "".join(cells)
    + "</root></mxGraphModel></diagram></mxfile>"
)
OUT.write_text(xml, encoding="utf-8")
print(f"wrote {OUT} ({len(cells)} cells)")
