# ServerShare
![Luvit](https://img.shields.io/badge/Luvit-v2.0-blue.svg?logo=lua&link=https%3A%2F%2Fluvit.io%2F)
![Version](https://img.shields.io/badge/Version-v1.2%20DeveloperBuild-darkblue.svg)
![Roblox](https://img.shields.io/badge/Made%20For-Roblox-red.svg?logo=roblox&link=https%3A%2F%2Froblox.com%2F)

A simple Discord bot that connects to a Roblox game.

Requires [**Luvit**](https://luvit.io/), [**Discordia**](https://github.com/SinisterRectus/Discordia).

## License

ServerShare is licensed under the GNU GPL v2 license. [View it here.](https://github.com/Dev0xz02/ServerShare/blob/main/LICENSE)

## Disclamer

**ServerShare is not designed for usage in script builders.**

If you see ServerShare running in a script builder, it is most likely with a custom loader and package.

## Setup

You need Luvit installed. To install Luvit, follow the instructions [here](https://luvit.io/install.html).

After you installed Luvit, you need to install all deps. Open the folder where is your ServerShare located, and run `lit install SinisterRectus/discordia`.

After you installed all deps required, now you need configure your `settings.json`. Here is the example of `settings.json`:

```json
{
    "token": "EXAMPLE.DISCORD.TOKEN", // Discord token here.
    "prefix": ";", // Your Discord's bot prefix here. Required.
    "splitkey": "/", // Split key. Required. Example: ;commands/2, ;ban/Player/Reason, ;kick/Player/Reason.

    "ownerId": "yourdiscordidhere", // Your Discord ID here. Required, or most commands wont execute.
    "appOnlyRoleId": "applicationmodroleidhere", // Application Mod Role ID here. Required, or you cant add/remove mods.
    "gameModRoleId": "gamemoderatorroleidhere", // Game Moderator Role ID here. Required, or you can't ban, kick etc.
    "gameDevId": "gamedeveloperidhere", // Game Developer Role ID here. Not required.

    "server": { // Required, or roblox game will not connect to the bot.
        "name": "server",
        "connectionkey": "connectionkey"
    }
}

// Please, remove any comments, or JSON file will not work!
```