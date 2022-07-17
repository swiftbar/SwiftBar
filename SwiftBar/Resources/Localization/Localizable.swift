import Foundation

enum Localizable {
    enum App: String {
        case ChoosePluginFolderTitle = "APP_CHOOSE_PLUGIN_FOLDER_TITLE"
        case FolderNotAllowedMessage = "APP_FOLDER_NOT_ALLOWED_MESSAGE"
        case FolderHasToManyFilesMessage = "APP_FOLDER_HAS_TOO_MANY_FILES_MESSAGE"
        case FolderNotAllowedAction = "APP_FOLDER_NOT_ALLOWED_ACTION"
        case ChoosePluginFolderMessage = "APP_CHOOSE_PLUGIN_FOLDER_MESSAGE"
        case ChoosePluginFolderInfo = "APP_CHOOSE_PLUGIN_FOLDER_INFO"
        case OKButton = "OK"
        case CancelButton = "CANCEL"
        case Quit = "APP_QUIT"
    }

    enum MenuBar: String {
        case SwiftBar = "MB_SWIFT_BAR"
        case UpdatingMenu = "MB_UPDATING_MENU"
        case LastUpdated = "MB_LAST_UPDATED"
        case AboutSwiftBar = "MB_ABOUT_SWIFT_BAR"
        case AboutPlugin = "MB_ABOUT_PLUGIN"
        case RunInTerminal = "MB_RUN_IN_TERMINAL"
        case DisablePlugin = "MB_DISABLE_PLUGIN"
        case DebugPlugin = "MB_DDEBUG_PLUGIN"
        case Preferences = "MB_PREFERENCES"
        case RefreshAll = "MB_REFRESH_ALL"
        case EnableAll = "MB_ENABLE_ALL"
        case DisableAll = "MB_DISABLE_ALL"
        case OpenPluginsFolder = "MB_OPEN_PLUGINS_FOLDER"
        case ChangePluginsFolder = "MB_CHANGE_PLUGINS_FOLDER"
        case GetPlugins = "MB_GET_PLUGINS"
        case SendFeedback = "MB_SEND_FEEDBACK"
        case ShowError = "MB_SHOW_ERROR"
    }

    enum Preferences: String {
        case Preferences = "PF_PREFERENCES"
        case General = "PF_GENERAL"
        case Plugins = "PF_PLUGINS"
        case PluginsFolder = "PF_PLUGINS_FOLDER"
        case Path = "PF_PATH"
        case PathIsNone = "PF_PATH_IS_NONE"
        case ChangePath = "PF_CHANGE_PATH"
        case Terminal = "PF_TERMINAL"
        case Shell = "PF_SHELL"
        case LaunchAtLogin = "PR_LAUNCH_AT_LOGIN"
        case IncludeBetaUpdates = "PR_INCLUDE_BETA_UPDATES"
        case HideSwiftBarIcon = "PF_HIDE_SWIFTBAR_ICON"
        case UpdateLabel = "PF_CHECK_FOR_UPDATE"
        case CheckForUpdates = "PF_CHECK_FOR_UPDATES"
        case NoPluginsMessage = "PF_NO_PLUGINS_MESSAGE"
        case EnableAll = "PF_ENABLE_ALL"
        case PluginsFootnote = "PF_PLUGINS_FOOTNOTE"
        case MenuBarItem = "PF_MENUBAR_ITEM"
        case DimOnManualRefresh = "PF_DIM_ON_MANUAL_REFRESH"
    }

    enum PluginRepository: String {
        case Category = "PR_CATEGORY"
        case PluginRepository = "PR_PLUGIN_REPOSITORY"
        case RefreshingDataMessage = "PR_REFRESHING_DATA_MESSAGE"
        case Dependencies = "PR_DEPENDENCIES"
        case PluginSource = "PR_PLUGIN_SOURCE"
        case AboutPlugin = "PR_ABOUT_PLUGIN"
        case AuthorPreposition = "PR_AUTORH_PREPOSITION"
        case InstallStatusInstall = "PR_INSTALL_STATUS_INSTALL"
        case InstallStatusInstalled = "PR_INSTALL_STATUS_INSTALLED"
        case InstallStatusFailed = "PR_INSTALL_STATUS_FAILED"
        case InstallStatusDownloading = "PR_INSTALL_STATUS_DOWNLOADING"
    }

    enum Categories: String {
        case aws = "CAT_AWS"
        case cryptocurrency = "CAT_CRYPTOCURRENCY"
        case dev = "CAT_DEV"
        case ecommerce = "CAT_E-COMMERCE"
        case email = "CAT_EMAIL"
        case environment = "CAT_ENVIRONMENT"
        case finance = "CAT_FINANCE"
        case games = "CAT_GAMES"
        case lifestyle = "CAT_LIFESTYLE"
        case messenger = "CAT_MESSENGER"
        case music = "CAT_MUSIC"
        case network = "CAT_NETWORK"
        case politics = "CAT_POLITICS"
        case science = "CAT_SCIENCE"
        case sports = "CAT_SPORTS"
        case system = "CAT_SYSTEM"
        case time = "CAT_TIME"
        case tools = "CAT_TOOLS"
        case travel = "CAT_TRAVEL"
        case tutorial = "CAT_TUTORIAL"
        case weather = "CAT_WEATHER"
        case web = "CAT_WEB"
    }
}

extension RawRepresentable where RawValue == String {
    var localized: String {
        NSLocalizedString(rawValue, comment: "")
    }
}
