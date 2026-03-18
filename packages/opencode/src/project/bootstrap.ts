import { Plugin } from "../plugin"
import { Format } from "../format"
import { LSP } from "../lsp"
import { FileWatcherService } from "../file/watcher"
import { File } from "../file"
import { Project } from "./project"
import { Bus } from "../bus"
import { Command } from "../command"
import { Instance } from "./instance"
import { VcsService } from "./vcs"
import { Log } from "@/util/log"
import { ShareNext } from "@/share/share-next"
import { runPromiseInstance } from "@/effect/runtime"
import { dbg } from "@/intranet/config"

export async function InstanceBootstrap() {
  dbg("bootstrap: start")
  Log.Default.info("bootstrapping", { directory: Instance.directory })
  dbg("bootstrap: Plugin.init start")
  await Plugin.init()
  dbg("bootstrap: Plugin.init done")
  ShareNext.init()
  dbg("bootstrap: ShareNext.init done")
  await Format.init()
  dbg("bootstrap: Format.init done")
  await LSP.init()
  dbg("bootstrap: LSP.init done")
  await runPromiseInstance(FileWatcherService.use((service) => service.init()))
  dbg("bootstrap: FileWatcher done")
  File.init()
  dbg("bootstrap: File.init done")
  await runPromiseInstance(VcsService.use((s) => s.init()))
  dbg("bootstrap: Vcs.init done")

  Bus.subscribe(Command.Event.Executed, async (payload) => {
    if (payload.properties.name === Command.Default.INIT) {
      await Project.setInitialized(Instance.project.id)
    }
  })
  dbg("bootstrap: complete")
}
