require 'sketchup.rb'
require 'win32ole'
require 'base64'
require 'tempfile'
require 'shellwords'


module Chroma
  PLUGIN_PATH = "Plugins/cz_vcb_exact"

  def self.enter_exact_vcb
    file = Tempfile.new('cz_vcb')
    file.close
    # https://stackoverflow.com/a/47639662
    script = READ_VCB_SCRIPT + Shellwords.escape(file.path)
    encoded = Base64.strict_encode64(script.encode('utf-16le'))
    command = "powershell.exe -encodedCommand #{encoded}"
    # run command WITHOUT showing window
    # https://www.ruby-forum.com/t/hiding-the-command-window-when-using-system-on-windows/75495/4
    result = @@wsh.Run(command, 0, 1)
    if result == 0
      file.open
      vcb_value = file.read
      puts "VCB: " + vcb_value
      # TODO: filter out tildes
      @@wsh.SendKeys(vcb_value + "~")
    else
      UI.messagebox('Error reading from VCB')
    end
    file.unlink
  end

  unless file_loaded?(__FILE__)
    @@wsh = WIN32OLE.new('Wscript.Shell')
    UI.menu.add_item('Enter Exact VCB') {
      enter_exact_vcb
    }
  end

  # the following is PowerShell code
  READ_VCB_SCRIPT = %q{
    using namespace System.Windows.Automation
    Add-Type -AssemblyName UIAutomationClient

    $focused = [AutomationElement]::FocusedElement
    # search up until we find the window
    # https://www.meziantou.net/detect-the-opening-of-a-new-window-in-csharp.htm
    while ($focused.Current.ControlType -ne [ControlType]::Window) {
      $focused = [TreeWalker]::RawViewWalker.GetParent($focused)
      if ($null -eq $focused) {
        exit 1
      }
    }
    $findVCBEdit = New-Object PropertyCondition ([AutomationElement]::AutomationIdProperty), "24214"
    $vcbEdit = $focused.FindFirst("Descendants", $findVCBEdit)
    if ($null -eq $vcbEdit) {
      exit 1
    }
    $vcbValue = $vcbEdit.Current.Name
    Set-Content -Value $vcbValue -Path }  # file name goes here!
end