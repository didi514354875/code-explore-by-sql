/******************************************************************************
 * The MIT License (MIT)
 *
 * Copyright (c) 2018-2026 Baldur Karlsson
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 ******************************************************************************/

#include "vk_test.h"

RD_TEST(VK_Bridge_Capture, VulkanGraphicsTest)
{
  static constexpr const char *Description =
      "Draws a triangle on one Vulkan instance while a second non-presenting instance submits "
      "work; capturing the first must capture both";

  int main()
  {
    // initialise, create window, create context, etc - this is instance A
    if(!Init())
      return 3;

    VkPipelineLayout layout = createPipelineLayout(vkh::PipelineLayoutCreateInfo());

    vkh::GraphicsPipelineCreateInfo pipeCreateInfo;

    pipeCreateInfo.layout = layout;
    pipeCreateInfo.renderPass = mainWindow->rp;

    pipeCreateInfo.vertexInputState.vertexBindingDescriptions = {vkh::vertexBind(0, DefaultA2V)};
    pipeCreateInfo.vertexInputState.vertexAttributeDescriptions = {
        vkh::vertexAttr(0, 0, DefaultA2V, pos),
        vkh::vertexAttr(1, 0, DefaultA2V, col),
        vkh::vertexAttr(2, 0, DefaultA2V, uv),
    };

    pipeCreateInfo.stages = {
        CompileShaderModule(VKDefaultVertex, ShaderLang::glsl, ShaderStage::vert, "main"),
        CompileShaderModule(VKDefaultPixel, ShaderLang::glsl, ShaderStage::frag, "main"),
    };

    VkPipeline pipe = createGraphicsPipeline(pipeCreateInfo);

    AllocatedBuffer vb(
        this,
        vkh::BufferCreateInfo(sizeof(DefaultTri),
                              VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT),
        VmaAllocationCreateInfo({0, VMA_MEMORY_USAGE_CPU_TO_GPU}));

    vb.upload(DefaultTri);

    // second, headless Vulkan instance B: no window, no swapchain, no presentation. It goes
    // through the layer like instance A, so it registers as a bridged capturer too.
    VkInstance instB = VK_NULL_HANDLE;
    VkPhysicalDevice physB = VK_NULL_HANDLE;
    VkDevice devB = VK_NULL_HANDLE;
    VkQueue queueB = VK_NULL_HANDLE;
    VkCommandPool poolB = VK_NULL_HANDLE;
    VkCommandBuffer cmdB = VK_NULL_HANDLE;

    {
      VkInstanceCreateInfo instInfo = {};
      instInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
      CHECK_VKR(vkCreateInstance(&instInfo, NULL, &instB));

      uint32_t physCount = 0;
      CHECK_VKR(vkEnumeratePhysicalDevices(instB, &physCount, NULL));
      TEST_ASSERT(physCount > 0, "Expected at least one physical device on instance B");

      std::vector<VkPhysicalDevice> physDevices(physCount);
      CHECK_VKR(vkEnumeratePhysicalDevices(instB, &physCount, physDevices.data()));
      physB = physDevices[0];

      std::vector<VkQueueFamilyProperties> queueProps;
      vkh::getQueueFamilyProperties(queueProps, physB);

      uint32_t queueFamilyB = ~0U;
      for(size_t i = 0; i < queueProps.size(); i++)
      {
        if(queueProps[i].queueFlags & VK_QUEUE_GRAPHICS_BIT)
        {
          queueFamilyB = (uint32_t)i;
          break;
        }
      }
      TEST_ASSERT(queueFamilyB != ~0U, "Expected a graphics queue family on instance B");

      float queuePriority = 1.0f;
      VkDeviceQueueCreateInfo queueInfo = {};
      queueInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
      queueInfo.queueFamilyIndex = queueFamilyB;
      queueInfo.queueCount = 1;
      queueInfo.pQueuePriorities = &queuePriority;

      VkDeviceCreateInfo devInfo = {};
      devInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
      devInfo.queueCreateInfoCount = 1;
      devInfo.pQueueCreateInfos = &queueInfo;

      CHECK_VKR(vkCreateDevice(physB, &devInfo, NULL, &devB));

      vkGetDeviceQueue(devB, queueFamilyB, 0, &queueB);

      VkCommandPoolCreateInfo poolInfo = vkh::CommandPoolCreateInfo(0, queueFamilyB);
      CHECK_VKR(vkCreateCommandPool(devB, &poolInfo, NULL, &poolB));

      VkCommandBufferAllocateInfo cmdInfo = {};
      cmdInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
      cmdInfo.commandPool = poolB;
      cmdInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
      cmdInfo.commandBufferCount = 1;
      CHECK_VKR(vkAllocateCommandBuffers(devB, &cmdInfo, &cmdB));
    }

    while(Running())
    {
      // instance A: normal windowed triangle frame
      VkCommandBuffer cmd = GetCommandBuffer();

      vkBeginCommandBuffer(cmd, vkh::CommandBufferBeginInfo());

      VkImage swapimg =
          StartUsingBackbuffer(cmd, VK_ACCESS_TRANSFER_WRITE_BIT, VK_IMAGE_LAYOUT_GENERAL);

      vkCmdClearColorImage(cmd, swapimg, VK_IMAGE_LAYOUT_GENERAL,
                           vkh::ClearColorValue(0.2f, 0.2f, 0.2f, 1.0f), 1,
                           vkh::ImageSubresourceRange());

      vkCmdBeginRenderPass(
          cmd, vkh::RenderPassBeginInfo(mainWindow->rp, mainWindow->GetFB(), mainWindow->scissor),
          VK_SUBPASS_CONTENTS_INLINE);

      vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe);
      vkCmdSetViewport(cmd, 0, 1, &mainWindow->viewport);
      vkCmdSetScissor(cmd, 0, 1, &mainWindow->scissor);
      vkh::cmdBindVertexBuffers(cmd, 0, {vb.buffer}, {0});
      vkCmdDraw(cmd, 3, 1, 0, 0);

      vkCmdEndRenderPass(cmd);

      FinishUsingBackbuffer(cmd, VK_ACCESS_TRANSFER_WRITE_BIT, VK_IMAGE_LAYOUT_GENERAL);

      vkEndCommandBuffer(cmd);

      Submit(0, 1, {cmd});

      Present();

      // instance B: headless submit on its own instance
      vkBeginCommandBuffer(cmdB, vkh::CommandBufferBeginInfo());

      VkMemoryBarrier memBarrier = {};
      memBarrier.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER;
      memBarrier.srcAccessMask = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT;
      memBarrier.dstAccessMask = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT;
      vkCmdPipelineBarrier(cmdB, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
                           VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0, 1, &memBarrier, 0, NULL, 0, NULL);

      vkEndCommandBuffer(cmdB);

      VkSubmitInfo submitInfo = {};
      submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
      submitInfo.commandBufferCount = 1;
      submitInfo.pCommandBuffers = &cmdB;
      CHECK_VKR(vkQueueSubmit(queueB, 1, &submitInfo, VK_NULL_HANDLE));
      vkQueueWaitIdle(queueB);

      if(curFrame > 200)
        break;
    }

    vkQueueWaitIdle(queueB);
    vkDestroyCommandPool(devB, poolB, NULL);
    vkDestroyDevice(devB, NULL);
    vkDestroyInstance(instB, NULL);

    return 0;
  }
};

REGISTER_TEST();
