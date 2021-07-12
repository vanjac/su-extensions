require 'sketchup.rb'
require 'win32ole'
require 'base64'

module Chroma
  PLUGIN_PATH = "Plugins/cz_vcb_exact"

  def self.enter_exact_vcb
    # https://stackoverflow.com/a/47639662
    encoded = Base64.strict_encode64(READ_VCB_SCRIPT.encode('utf-16le'))
    command = "powershell.exe -encodedCommand #{encoded}"
    # run command WITHOUT showing window
    # https://www.ruby-forum.com/t/hiding-the-command-window-when-using-system-on-windows/75495/4
    puts @@wsh.Run(command, 0, 1)
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
    $AssemblyPath = "$env:programfiles\Reference Assemblies\Microsoft\Framework\v3.0"
    # TODO: try -AssemblyName System.Windows.Automation instead
    Add-Type -Path "$AssemblyPath\UIAutomationClient.dll"
    Add-Type -Path "$AssemblyPath\UIAutomationTypes.dll"
    
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

    $wshell = New-Object -ComObject wscript.shell;
    # https://stackoverflow.com/a/17851491
    # TODO filter out tilde
    $wshell.SendKeys($vcbEdit.Current.Name + "~")
  }
end