from discord_webhook import DiscordEmbed, DiscordWebhook as dw

def build(username, urls, title, description, color=None):
    # If the Feeder Name is a link pull out the text:
    if '[' in username and ']' in username:
        username = username.split('[')[1].split(']')[0]

    if '\"' in username:
        username = username.strip('\"')

    if color is None:
        color = 0x007bff  # Blue
    embed = DiscordEmbed(title=title, color=color, description=description)
    embed.set_footer(text="Planefence by kx1t - https://planefence.com")

    webhooks = dw.create_batch(urls=urls, username=username)

    for webhook in webhooks:
        webhook.add_embed(embed)

    return webhooks, embed

def field(embed, name, value, inline=None):
    if inline is None:
        inline = True
    embed.add_embed_field(name=name, value=value, inline=inline)
