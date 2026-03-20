import { Plugin } from "../plugin"
import { LSP } from "../lsp"
import { File } from "../file"
import { Project } from "./project"
import { Bus } from "../bus"
import { Command } from "../command"
import { Instance } from "./instance"
import { Log } from "@/util/log"
import { ShareNext } from "@/share/share-next"
import { dbg } from "@/intranet/config"

export async function InstanceBootstrap() {
  dbg("bootstrap: start")
  Log.Default.info("bootstrapping", { directory: Instance.directory })
  dbg("bootstrap: Plugin.init start")
  await Plugin.init()
  dbg("bootstrap: Plugin.init done")
  ShareNext.init()
  dbg("bootstrap: ShareNext.init done")
  // Format, FileWatcher, and Vcs are now initialized via Effect LayerMap in instances.ts
  dbg("bootstrap: Format.init done")
  await LSP.init()
  dbg("bootstrap: LSP.init done")
  dbg("bootstrap: FileWatcher done")
  File.init()
  dbg("bootstrap: File.init done")
  dbg("bootstrap: Vcs.init done")

  Bus.subscribe(Command.Event.Executed, async (payload) => {
    if (payload.properties.name === Command.Default.INIT) {
      await Project.setInitialized(Instance.project.id)
    }
  })
  dbg("bootstrap: complete")
}
