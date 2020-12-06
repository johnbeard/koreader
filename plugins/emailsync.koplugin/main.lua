local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local DataStorage = require("datastorage")
local _ = require("gettext")
local logger = require("logger")
local imap4 = require("imap4")
local message = require("message")


local EmailSync = WidgetContainer:new{
    name = "emailsync",
    is_doc_only = false,
}

local initialized = false
local email_download_dir_name = "email"
local email_download_dir_path


function EmailSync:init()
    if not initialized then
        initialized = true
    end

    self:readSettings()

    email_download_dir_path = ("%s/%s"):format(DataStorage:getFullDataDir(),
        email_download_dir_name)

    if not lfs.attributes(email_download_dir_path, "mode") then
        logger.dbg("Email sync: Creating initial directory")
        lfs.mkdir(email_download_dir_path)
    end

    -- EmailSync:loadDefaults()
    self.ui.menu:registerToMainMenu(self)
end

function EmailSync:addToMainMenu(menu_items)
    menu_items.emailsync = {
        text = _("Email sync"),
        callback = function()
        end,
        sub_item_table = {
            {
                text = _("Sync now"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:syncEmail()
                end,
            },
            {
                text = _("Delete files from server after sync"),
                checked_func = function() return self.delete_synced end,
                callback = function()
                    self.delete_synced = not self.delete_synced
                    self:saveSettings()
                end
            },
            {
                text = _("Go to email download folder"),
                callback = function(touchmenu_instance)
                    self:goToDlFolder()
                end,
            },
            {
                text = _("IMAP Settings"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:handleSettings();
                end,
            },
        }
    }
end

function EmailSync:goToDlFolder()
    local FileManager = require("apps/filemanager/filemanager")
    if self.ui.document then
        self.ui:onClose()
    end
    if FileManager.instance then
        FileManager.instance:reinit(email_download_dir_path)
    else
        FileManager:showFiles(email_download_dir_path)
    end
end

function EmailSync:handleSettings()
    local MultiInputDialog = require("ui/widget/multiinputdialog")
    local settings_dialog
    settings_dialog = MultiInputDialog:new{
        title = _("Set IMAP server settings"),
        fields = {
            {
                text = self.imap_server,
                input_type = "string",
                hint = _("Server domain (e.g. imap.gmail.com"),
            },
            {
                text = self.imap_port,
                input_type = "number",
                hint = _("Port (e.g. 993)"),
            },
            {
                text = self.imap_username,
                input_type = "string",
                hint = _("Username"),
            },
            {
                text = self.imap_password,
                input_type = "string",
                text_type = "password",
                hint = _("Password"),
            },
            {
                text = self.imap_mailbox,
                input_type = "string",
                hint = _("Mailbox to sync from"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(settings_dialog)
                    end
                },
                {
                    text = _("OK"),
                    callback = function()
                        local fields = settings_dialog:getFields()
                        local url = fields[1]
                        local port = tonumber(fields[2])
                        if url ~= "" then
                            if port and port < 65355 then
                                self.imap_server = url
                                self.imap_port = port
                            end
                            self.imap_username = fields[3]
                            self.imap_password = fields[4]
                            self.imap_mailbox = fields[5]
                            self:saveSettings()
                        end
                        UIManager:close(settings_dialog)
                    end
                }
            }
        }
    }
    UIManager:show(settings_dialog)
    settings_dialog:onShowKeyboard()
end

function EmailSync:readSettings()
    local settings = G_reader_settings:readSetting("emailsync") or {}
    self.imap_server = settings.imap_server or ""
    self.imap_port = settings.imap_port or 993
    self.imap_username = settings.imap_username or ""
    self.imap_password = settings.imap_password or ""
    self.imap_mailbox = settings.imap_mailbox or "Inbox"
    self.delete_synced = settings.delete_synced or false
end

function EmailSync:saveSettings()

    local settings = {
        imap_server = self.imap_server,
        imap_port = self.imap_port,
        imap_protocol = self.imap_protocol,
        imap_username = self.imap_username,
        imap_password = self.imap_password,
        imap_mailbox = self.imap_mailbox,
    }
    G_reader_settings:saveSetting("emailsync", settings)
    logger.dbg("Saving settings", settings)
end

function EmailSync:syncEmail()
    logger.dbg("SYNCING EMAIL!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
    -- local connection = imap4(self.imap_server, self.imap_port)
    local connection = imap4(self.imap_server, self.imap_port)

    connection:enabletls{protocol = "tlsv1_3"}

    assert(connection:isCapable("IMAP4rev1"))

    connection:login(self.imap_username, self.imap_password)

    local info = connection:select(self.imap_mailbox)
    logger.dbg("Selected mailbox", self.imap_mailbox)
    logger.dbg("Exist; recent: ", info.exist, info.recent)

    -- list of email IDs to get
    local id_list;

    id_list = connection:search("or seen UNSEEN")

    for _, id in pairs(id_list) do
        print(id)

        local fetch = connection:fetch("RFC822", tostring(id))
        -- logger.dbg(fetch) -- long!
        print("-------------------------")
        local msg = message(fetch[1].RFC822)
        local saved = false
        print("ID:         ", msg:id())
        print("subject:    ", msg:subject())
        print("to:         ", msg:to())
        print("from:       ", msg:from())
        print("from addr:  ", msg:from_address())
        print("reply:      ", msg:reply_to())
        print("reply addr: ", msg:reply_address())
        print("trunc:      ", msg:is_truncated())
        for i, v in ipairs(msg:full_content()) do
            if v.text then  print("  ", i , "TEXT: ", v.type, #v.text)
            else
                local name = v.file_name or v.name
                print("  ", i , "FILE: ", v.type, name, #v.data)
                -- print(v.data)

                local attachment_save_path = ("%s/%s"):format(email_download_dir_path, name)
                local f = io.open(attachment_save_path, "wb")
                f:write(v.data)
                f:close()

                logger.dbg("successfully created:", attachment_save_path)
                saved = true
            end
        end

        -- if saved and self.delete_synced then

        -- end

        collectgarbage()

        break
    end
end


return EmailSync