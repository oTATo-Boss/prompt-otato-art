#!/usr/bin/env python3
"""Create the Chinese offline installation guide shipped alongside the DMG in the download ZIP."""
from pathlib import Path
import argparse

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "packaging/dmg/安装说明.pdf"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--font", type=Path, required=True, help="Noto Sans SC static TrueType font")
args = parser.parse_args()
pdfmetrics.registerFont(TTFont("NotoSC", str(args.font)))
BLUE = colors.HexColor("#246BFF")
INK = colors.HexColor("#15233B")
MUTED = colors.HexColor("#596579")
WIDTH, HEIGHT = A4

pdf = canvas.Canvas(str(OUTPUT), pagesize=A4)
pdf.setTitle("oTATo prompt - 安装与首次打开")
pdf.setAuthor("oTATo")
pdf.setFillColor(BLUE)
pdf.rect(0, HEIGHT - 13, WIDTH, 13, fill=1, stroke=0)


def text(value, x, top, width, size=12, color=INK, leading=None):
    style = ParagraphStyle("body", fontName="NotoSC", fontSize=size,
                           leading=leading or size * 1.55, textColor=color,
                           alignment=TA_LEFT, wordWrap="CJK")
    paragraph = Paragraph(value, style)
    _, height = paragraph.wrap(width, HEIGHT)
    paragraph.drawOn(pdf, x, HEIGHT - top - height)
    return height


text("oTATo prompt", 42, 40, 500, size=17, color=BLUE)
text("安装与首次打开", 42, 77, 510, size=28)
text("macOS 14 及以上 · Apple Silicon / Intel", 42, 124, 510,
     size=11, color=MUTED)
pdf.setFillColor(colors.HexColor("#EDF3FF"))
pdf.roundRect(42, HEIGHT - 223, WIDTH - 84, 66, 10, fill=1, stroke=0)
text("未公证版本首次打开可能显示“无法验证开发者”或“Apple 无法检查是否包含恶意软件”。请确认安装包来自官网，再按下面的步骤打开。若已正常启动，无需额外设置。",
     56, 166, WIDTH - 112, size=11.5)


def step(number, title, body, top):
    pdf.setFillColor(BLUE)
    pdf.circle(55, HEIGHT - top - 13, 13, fill=1, stroke=0)
    pdf.setFillColor(colors.white)
    pdf.setFont("Helvetica-Bold", 12)
    pdf.drawCentredString(55, HEIGHT - top - 17, str(number))
    text(title, 80, top - 2, WIDTH - 122, size=16)
    height = text(body, 80, top + 28, WIDTH - 122, size=12)
    return top + 28 + height + 22


top = step(1, "先解压 ZIP，阅读本教程",
           "官网下载的是 ZIP。双击解压后，可直接打开“安装说明.pdf”；无需先打开 DMG。确认来源后，再双击 oTATo-prompt.dmg。", 244)
top = step(2, "DMG 被阻止打开时",
           "先关闭提醒，打开“系统设置 → 隐私与安全性”，向下找到“安全性”。核对被阻止的文件名，点“仍要打开”，再按提示验证并点“打开”。未被阻止可直接继续。", top)
top = step(3, "拖入“应用程序”",
           "打开 DMG 后，把 oTATo Prompt.app 拖到右侧“应用程序”文件夹。复制完成后，从“应用程序”中运行软件，不要直接在 DMG 里运行。", top)
top = step(4, "首次启动软件",
           "从“应用程序”双击 oTATo Prompt。若 App 也被阻止，先关闭提醒，再按第 2 步为这个 App 允许打开。同一版本被允许后，日常使用可正常启动。", top)

pdf.setStrokeColor(colors.HexColor("#D9E2EF"))
pdf.line(42, HEIGHT - top, WIDTH - 42, HEIGHT - top)
text("没有看到“仍要打开”？", 42, top + 12, WIDTH - 84, size=13)
text("先尝试打开被阻止的 DMG 或 App，再查看系统设置；App 应先复制到“应用程序”。受管理的 Mac 可能限制此操作。遇到“已损坏”或“将损坏电脑”的提醒时，请停止安装，重新从官网下载并反馈。",
     42, top + 36, WIDTH - 84, size=10.5, color=MUTED)

text('官网与在线说明：<link href="https://prompt.otato.art/help" color="#246BFF">prompt.otato.art/help</link>',
     42, 778, WIDTH - 84, size=10, color=MUTED)
text('步骤依据：<link href="https://support.apple.com/zh-cn/102445" color="#246BFF">Apple：在 Mac 上安全地打开 App</link>',
     42, 798, WIDTH - 84, size=9, color=MUTED)
pdf.showPage()
pdf.save()
print(OUTPUT)
