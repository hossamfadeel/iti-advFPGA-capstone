<AutoPilot:project xmlns:AutoPilot="com.autoesl.autopilot.project" top="replay_gov" name="replay_gov_proj" ideType="classic">
    <files>
        <file name="src/replay_gov.cpp" sc="0" tb="false" cflags="" csimflags="" blackbox="false"/>
        <file name="../../tb/tb_replay_gov.cpp" sc="0" tb="1" cflags="-I../../src -Wno-unknown-pragmas" csimflags="" blackbox="false"/>
    </files>
    <solutions>
        <solution name="sol1" status=""/>
    </solutions>
    <Simulation argv="">
        <SimFlow name="csim" setup="false" optimizeCompile="false" clean="false" ldflags="" mflags=""/>
    </Simulation>
</AutoPilot:project>
