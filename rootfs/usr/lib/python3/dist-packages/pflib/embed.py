import discord_webhook as discord

def build(title, description, color=None):
    if color is None:
        color = 0x007bff  # Blue
    embed = discord.DiscordEmbed(title=title, color=color, description=description)
    embed.set_footer(text="Planefence by kx1t - docker:kx1t/planefence")
    return embed

def field(embed, name, value, inline=None):
    if inline is None:
        inline = True
    embed.add_embed_field(name=name, value=value, inline=inline)
