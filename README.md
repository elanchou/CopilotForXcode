# Copilot for Xcode <img alt="Logo" src="/AppIcon.png" align="right" height="50">

![ScreenRecording](/ScreenRecording.gif)

Copilot for Xcode is an Xcode Source Editor Extension that provides Github Copilot support for Xcode. It uses the LSP provided through [Copilot.vim](https://github.com/github/copilot.vim/tree/release/copilot/dist).

Thanks to [LSP-copilot](https://github.com/TerminalFi/LSP-copilot) for showing the way to interact with Copilot. And thanks to [LanguageClient](https://github.com/ChimeHQ/LanguageClient) for the Language Server Protocol support in Swift.

## Prerequisites

- [Node](https://nodejs.org/) installed to run the Copilot LSP.
- Public network connection.
- Active GitHub Copilot subscription.  

## Installation and Setup

1. Download the Copilot for Xcode.app from the latest release, and extract it to the Applications folder.
2. Open the app, and click "Set Up Launch Agents" to set up a background running XPC Service that does the real job.
3. Refresh the Copilot status, if it fails, quit and restart the app. 
4. Sign in. You will be directed to a verification website provided by GitHub, and a user code will be pasted into your clipboard.
5. After signing in, go back to the app and click "Confirm Sign-in" to finish.
5. Enable the extension in the Settings.app, then maybe restart Xcode.

The first time the actions run, the extension will ask for 2 types of permissions:
1. Accessibility API: which the extension uses to get the editing file path.
2. Folder Access: the extension needs, to run some Apple Scripts to get the project/workspace path. 

## Limitations

- The first run of the extension will be slow. Be patient.
- The extension uses some dirty tricks to get the file and project/workspace paths. It may fail, it may be incorrect, especially when you have multiple Xcode windows running, and maybe even worse when they are in different displays. I am not sure about that though.
- The suggestions are presented as C-style comments, they may break your code if you are editing a JSON file or something.

## FAQ

**Q: The extension doesn't show up in the `Editor` menu.**

> A: Please make sure it's turned on in `Settings.app > Privacy & Security > Extensions > Xcode Source Editor Extension`.

**Q: The extension says it can't connect to the XPC service / helper.**

> A: Please make sure you have set up Launch Agents, try running `launchctl list | grep com.intii` from the terminal, and see if `com.intii.CopilotForXcode.XPCService` exists. If not, check `~/Library/LaunchAgents` to see if `com.intii.CopilotForXcode.XPCService.plist` exists. If they don't, and the button in the app fails to create them, please try to do it by hand.

**Q: The extension complains that it has no access to the Accessibility API**

> A: Check the list in `Settings.app > Privacy & Security > Accessibility`. Turn the toggle on for `Copilot for Xcode`. If it's not on the list, add it manually.
>  
> If you have just **updated the app**, consider trying removing the Launch Agents and set it up again!

**Q: Will it work in future Xcode updates?**

> A: I don't know. This extension uses many tricks to do its job, and these tricks can break in the future. 

## How It Works
Check my [other extension](https://github.com/intitni/XccurateFormatter), you can find a short introduction there. 

## Todo

- [ ] Auto trigger Copilot while editing (I have some ideas but not sure if they will work).
