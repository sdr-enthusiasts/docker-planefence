import discord

from . import log

def build(title, description, color=None):
    if color is None:
        color = 0x007bff  # Blue
    embed = discord.Embed(title=title, color=color, description=description)
    embed.set_footer(text="Planefence by kx1t - docker:kx1t/planefence")
    return embed

def field(embed, name, value, inline=None):
    if inline is None:
        inline = True
    embed.add_field(name=name, value=value, inline=inline)

def media(embed, config, icao):
    if config.get("DISCORD_MEDIA") == "screenshot":
        if config.get("PF_SCREENSHOTURL", "") == "":
            log("[ERROR] Discord is configured to attach screenshots but PF_SCREENSHOTURL is not configured")
            return None
        return pf.get_screenshot_file(config, icao)
