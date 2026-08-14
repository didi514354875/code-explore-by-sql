import renderdoc as rd
import rdtest


class VK_Bridge_Capture(rdtest.TestCase):
    demos_test_name = 'VK_Bridge_Capture'
    demos_frame_cap = 100
    demos_captures_expected = 2

    def check_capture(self):
        # captures[0] is the windowed instance's capture (its file finishes first:
        # the triggering instance ends before the cascade targets).
        last_action: rd.ActionDescription = self.get_last_action()

        self.controller.SetFrameEvent(last_action.eventId, True)

        self.check_triangle(out=last_action.copyDestination)
