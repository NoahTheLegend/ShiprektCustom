
void onRender(CSprite@ this)
{
    CBlob@ blob = this.getBlob();
    if (blob is null) return;

    CBlob@ occupier = getBlobByNetworkID(blob.get_u16("operatorid"));

    f32 distance = blob.get_f32("distance");
    //if (distance == 0) return;

    if (occupier !is null && occupier.getPlayer() !is null && occupier.isMyPlayer())
    {
        CControls@ controls = occupier.getControls();
        if (controls is null) return;

        Vec2f mspos = controls.getMouseScreenPos();
        Vec2f mpos = occupier.getAimPos();
        Vec2f diff = occupier.getPosition() - mpos;
        f32 dist = diff.Normalize();
        Vec2f aimVector = Vec2f(1, 0).RotateBy(occupier.getAngleDegrees()-blob.getAngleDegrees()+90);
        int scrw = getDriver().getScreenWidth();
        int scrh = getDriver().getScreenHeight();

        Vec2f vel_offset = blob.get_Vec2f("vel").RotateBy(-getCamera().getRotation())*16;

        if (dist <= distance)
            GUI::DrawIcon("MortarAim.png", Vec2f(-18.5, -18.5)+mspos+vel_offset);
        else // set icon to max distance radius border
            GUI::DrawIcon("MortarAim.png", Vec2f(-18.5, -18.5)+Vec2f(scrw/2, scrh/2)-aimVector*(distance+distance/4)+vel_offset);
    }   // -18.5 is offset to center of the cursor
}

void onTick(CSprite@ this)
{
    CBlob@ blob = this.getBlob();
    if (blob is null) return;

    Vec2f tr = this.getWorldTranslation();
    Vec2f otr = blob.get_Vec2f("otr");
    blob.set_Vec2f("vel", tr-otr);
    blob.set_Vec2f("otr", tr);
}