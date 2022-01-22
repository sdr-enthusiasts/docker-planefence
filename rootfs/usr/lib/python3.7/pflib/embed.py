import discord

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
        if config.get("SCREENSHOTURL", "") == "":
            return None
        return pf.get_screenshot_file(config, icao)
